#include <linux/module.h>
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/errno.h>
#include <rtai.h>
#include <rtai_sched.h>
#include <rtai_fifos.h>

#include "cfg.h"
#include "window.h"
#include "wavelet.h"
#include "svm.h"

#define KB  1024
#define MB  1024*KB

#define FIFO_DATA    0

// Base address (bar0)
#define PCIE_AVALONTOP  0x0000

#define AVALONTOP_WADDR   0x10
#define AVALONTOP_RFLAG   0x10
#define AVALONTOP_WSTOP   0x14
#define AVALONTOP_GSZREF  0x18
#define AVALONTOP_GTSDEQ  0x1c

#define AVALONTOP_DMINRDY 0x20
#define AVALONTOP_DMINSUM 0x24
#define AVALONTOP_DMINGET 0x28
#define AVALONTOP_DMINFBK 0x20

#define DMA_BITS 32
#define DMA_WORDS_REQUIRED_FOR_ALL_CH 3
#define WIN_MAX_SIZE 256
#define DMA_BUF_WORDS (2*DMA_WORDS_REQUIRED_FOR_ALL_CH*WIN_MAX_SIZE)
#define DMA_BUF_SIZE (DMA_BUF_WORDS*sizeof(uint64_t))

static void *avalontop_base;

static uint8_t n_devices = 0;

static uint32_t epoch = 1;
static uint64_t *dma_ptr = NULL;
static dma_addr_t dma_handle;

typedef enum {
    NotDetected = -1,
    Both = 0,
    OnlyA = 1,
    OnlyB = 2
} SpikesInWin;

// -------- FP/vector units context saving --------
static FPU_ENV saved_fpu_reg, our_fpu_reg;
static unsigned long saved_cr0;

// Called for each detected spike
// ts: spike timestamp
// individual: 1 for A, 2 for B
// alone_in_window: true if the window was OnlyA or OnlyB, false if it was Both
static void emit_result(uint32_t ts, int32_t individual, int32_t alone_in_window) {
    rtf_put(FIFO_DATA, (void*)&ts, sizeof(ts));
    rtf_put(FIFO_DATA, (void*)&individual, sizeof(individual));
    rtf_put(FIFO_DATA, (void*)&alone_in_window, sizeof(alone_in_window));
}

// Get the result from the DistMinimizer hardware module
static inline void distminimizer_get_result(SpikesInWin *spk, int *offA, int *offB) {
    while (!ioread32(avalontop_base + AVALONTOP_DMINRDY));
    uint32_t rotspk = ioread32(avalontop_base + AVALONTOP_DMINGET);
    //rt_printk("gymnort_recog: dmin result = %08x\n", regval);
    *spk = rotspk & 0xffff;
    if (*spk == Both) {
        const int rot = rotspk >> 16;
        *offA = (rot & 0x7f) << 1;
        *offB = ((((rot - 1) >> 7) + 1) & 0x7f) << 1;
    }
}

static inline void distminimizer_send_feedback(SpikesInWin feedback) {
    BUG_ON(feedback == NotDetected);
    iowrite32(feedback, avalontop_base + AVALONTOP_DMINFBK);
}

// Process a window received from the WindowMaker hardware module
// The caller is responsible for saving/restoring FP/vector unit state.
// Calls emit_result for each detected spike.
static void process_window(const void *in, const uint32_t ts, const int size, const int ref) {
    static float ALIGNED(32) sig[NumChannels][WaveletOutSize];
    static float ALIGNED(32) max_amplitude[NumChannels] = {};
    static double ALIGNED(32) features[NumFeatures];

    //-------------------------------
    // Classify all suitable channels

    prepare_window((const aint16 *)in, size, ref, sig);
    for (int ch = 0; ch < NumChannels; ch++)
        max_amplitude[ch] = scalar_max_abs_float8_arr(sig[ch], WaveletInSize);

    SpikesInWin svmResult = NotDetected;
    int svmChannels = 0;
    double minProb = 1.0;

    if (size <= MaxWinSizeForSVM) {
        for (int ch = 0; ch < NumChannels; ch++) {
            const float amp = max_amplitude[ch];
            if (amp >= OnlyAbove && amp <= SaturationThreshold) {
                dtcwpt_normed_fulltree(sig[ch]);
                svm_prepare_features(sig[ch], features);
                const double dec_val = svm_decision_value(features);

                if (dec_val >= 0.0)
                    svmResult = (svmResult == OnlyB || svmResult == Both) ? Both : OnlyA;
                else
                    svmResult = (svmResult == OnlyA || svmResult == Both) ? Both : OnlyB;

                const double prob = sigmoid_predict(dec_val);
                minProb = __builtin_fmin(minProb, __builtin_fmax(prob, 1.0-prob));

                ++svmChannels;
            }
        }
    }

    //rt_printk("gymnort_recog: SVM: ch=%d, prob=%d, result=%d\n", svmChannels, (int)(10000*minProb), svmResult);

    //--------------------------------------------
    // Obtain DistMinimizer hardware module result

    SpikesInWin dminResult;
    int offA = 0, offB = 0;
    static int fixA = 0, fixB = 0;
    distminimizer_get_result(&dminResult, &offA, &offB);
    //rt_printk("gymnort_recog: DMin: result=%d, offA=%d, offB=%d\n", dminResult, offA, offB);

    //----------------------------------------------------------------
    // Initialize DistMinimizer if SVM detects a high specificity pair

    static bool initialized = false;
    static int A_disagreement = 0, B_disagreement = 0;
    const uint32_t singleSpkTs = ts - ref;
 
    static SpikesInWin lastPairMemberResult = NotDetected;

    if (!initialized
            && (svmResult == OnlyA || svmResult == OnlyB)
            && (size <= HighSpecMaxWinSize)
            && (svmChannels >= HighSpecMinCh)
            && (minProb >= HighSpecProbThreshold)) {

        distminimizer_send_feedback(svmResult);

        static uint32_t lastSvmTs = 0;

        if (((svmResult == OnlyA && lastPairMemberResult == OnlyB) ||
             (svmResult == OnlyB && lastPairMemberResult == OnlyA))
             && singleSpkTs - lastSvmTs <= HighSpecInterval) {
            lastPairMemberResult = NotDetected;
            initialized = true;
        }
        else {
            lastPairMemberResult = svmResult;
            lastSvmTs = singleSpkTs;
        }

        if (svmResult == OnlyA) {
            fixA = size - ref;
            A_disagreement = 0;
        }
        else {
            fixB = size - ref;
            B_disagreement = 0;
        }

        return;
    }

    lastPairMemberResult = NotDetected;

    //-------------------------------------------------
    // Otherwise, if SVM does not have high specificity

    SpikesInWin feedback, result;
    bool disagreement = false;

    if (dminResult == svmResult || svmResult == NotDetected) {
        // Just use and feedback the result if SVM and DistMinimizer agree
        feedback = result = dminResult;
    }
    else if (initialized
            && (size <= HighSpecMaxWinSize)
            && (minProb >= HighSpecProbThreshold)
            && ((svmResult == OnlyA && A_disagreement >= ContinuityHysteresis) ||
                (svmResult == OnlyB && B_disagreement >= ContinuityHysteresis))) {
        // Use and feedback OnlyA/OnlyB if disagreement is above the hysteresis
        feedback = result = svmResult;
    }
    else {
        // Otherwise, use DistMinimizer but skip an auto-feedback
        //result = dminResult;
        //feedback = Both;
        feedback = result = dminResult;
        disagreement = true;
    }

    if (disagreement) {
        if (svmResult == OnlyA)
            ++A_disagreement;
        else if (svmResult == OnlyB)
            ++B_disagreement;
    }
    else {
        if (result == OnlyA) {
            fixA = size - ref;
            A_disagreement = 0;
        }
        else if (result == OnlyB) {
            fixB = size - ref;
            B_disagreement = 0;
        }
    }

    //--------------------------------
    // Emit final feedback and results

    distminimizer_send_feedback(feedback);

    if (initialized) {
        if (result == OnlyA || result == OnlyB) {
            emit_result(singleSpkTs, result, true);
        }
        else {
            const uint32_t base_ts = ts - size;
            const int posA = (offA + fixA) & 0xff;
            const int posB = (offB + fixB) & 0xff;
            if (posA < posB) {
                emit_result(base_ts + posA, OnlyA, false);
                emit_result(base_ts + posB, OnlyB, false);
            }
            else {
                emit_result(base_ts + posB, OnlyB, false);
                emit_result(base_ts + posA, OnlyA, false);
            }
        }
    }
}

// -------- Interrupt handler --------
static int irq_handler(unsigned irq, void *cookie_) {
    const uint32_t flag = ioread32(avalontop_base + AVALONTOP_RFLAG);
    const int irq_is_ours = (flag == epoch);
    //rt_printk("gymnort_recog: got IRQ, flag=%d, is_ours=%d.\n", flag, irq_is_ours);

    if (likely(irq_is_ours)) {
        const int firstIndex = (flag % 2 == 1) ? 0 : DMA_BUF_WORDS/2;
        const uint32_t refsz = ioread32(avalontop_base + AVALONTOP_GSZREF);
        const int size = refsz & 0xffff;
        const int ref = refsz >> 16;
        const uint32_t ts = ioread32(avalontop_base + AVALONTOP_GTSDEQ);

        save_fpcr_and_enable_fpu(saved_cr0);
        save_fpenv(saved_fpu_reg);
        restore_fpenv(our_fpu_reg);

        process_window((void*)&dma_ptr[firstIndex], ts, size, ref);

        save_fpenv(our_fpu_reg);
        restore_fpenv(saved_fpu_reg);
        restore_fpcr(saved_cr0);

        ++epoch;
    }

    rt_unmask_irq(irq);
    return irq_is_ours;
}


static struct pci_device_id pci_ids[] = {
    { PCI_DEVICE(0x1172, 0x0de4), }, // Demo numbers
    { 0, }
};
MODULE_DEVICE_TABLE(pci, pci_ids);

static int pci_probe(struct pci_dev *dev, const struct pci_device_id *id);
static void pci_remove(struct pci_dev *dev);

static struct pci_driver pci_driver = {
    .name       = "gymnort_recog",
    .id_table   = pci_ids,
    .probe      = pci_probe,
    .remove     = pci_remove,
};

static int pci_probe(struct pci_dev *dev, const struct pci_device_id *id) {
    unsigned long resource;
    int retval;

    if (++n_devices > 1)
        return -EOVERFLOW;

    retval = pci_enable_device(dev);

    if (retval) {
        rt_printk("gymnort_recog: ERROR: Unable to enable device: %d\n",retval);
        return retval;
    }
    else
        rt_printk("gymnort_recog: device enabled!\n");

    // Allow device to master the bus (required for DMA)
    pci_set_master(dev);

    // Set coherent DMA address limitation
    retval = pci_set_consistent_dma_mask(dev, DMA_BIT_MASK(DMA_BITS));
    if (retval) {
        rt_printk("gymnort_recog: ERROR: Unable to set DMA bit mask: %d\n", retval);
        return retval;
    }

    // Allocate a memory block suitable for coherent DMA
    dma_ptr = dma_alloc_coherent(&dev->dev, DMA_BUF_SIZE, &dma_handle, GFP_KERNEL);
    if (dma_ptr == NULL) {
        rt_printk("gymnort_recog: could not allocate memory for DMA\n");
        return -ENOMEM;
    }

    rt_printk("gymnort_recog: Allocated coherent memory: dma_handle=0x%x, ptr=%p\n", dma_handle, dma_ptr);

    // Gets a pointer to bar0
    resource = pci_resource_start(dev,0);
    avalontop_base = ioremap_nocache(resource + PCIE_AVALONTOP, 16);

    // Read vendor ID
    rt_printk("gymnort_recog: Found Vendor id: 0x%0.4x\n", dev->vendor);
    rt_printk("gymnort_recog: Found Device id: 0x%0.4x\n", dev->device);

    // Read IRQ Number
    rt_printk("gymnort_recog: Found IRQ: %d\n", dev->irq);

    // Request IRQ and install handler
    retval = rt_request_irq(dev->irq, irq_handler, NULL, 0);
    if (retval) {
        rt_printk("gymnort_recog: request_irq failed!\n");
        return retval;
    }

    rt_startup_irq(dev->irq);

    rt_printk("gymnort_recog: enabling WindowDMA\n");
    iowrite32(dma_handle, avalontop_base + AVALONTOP_WADDR);

    return 0;
}

static void pci_remove(struct pci_dev *dev) {

    rt_release_irq(dev->irq);

    --n_devices;

    if (dma_ptr != NULL)
        dma_free_coherent(&dev->dev, DMA_BUF_SIZE, dma_ptr, dma_handle);

    iounmap(avalontop_base);

    pci_set_drvdata(dev,NULL);
    rt_printk("gymnort_recog: Interrupt handler uninstalled.\n");
}

/*******************************
 *  Driver Init/Exit Functions *
 *******************************/

static int __init m_init(void) {
    int retval;

    save_fpenv(our_fpu_reg);

    rtf_create(FIFO_DATA, 16*MB);

    // Register PCI Driver
    // IRQ is requested on pci_probe
    retval = pci_register_driver(&pci_driver);
    if (retval)
        rt_printk("gymnort_recog: ERROR: cannot register pci.\n");
    else
        rt_printk("gymnort_recog: pci driver registered.\n");

    return retval;
}

static void __exit m_exit(void) {
    iowrite32(0, avalontop_base + AVALONTOP_WSTOP);

    rtf_destroy(FIFO_DATA);

    pci_unregister_driver(&pci_driver);
    rt_printk("gymnort_recog: pci driver unregistered.\n");
}

module_init(m_init);
module_exit(m_exit);
MODULE_LICENSE("GPL");
