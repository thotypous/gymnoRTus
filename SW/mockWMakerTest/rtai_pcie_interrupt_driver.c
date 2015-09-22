#include <linux/module.h>
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/errno.h>
#include <rtai.h>
#include <rtai_sched.h>
#include <rtai_fifos.h>

#define KB  1024
#define MB  1024*KB

#define FIFO_DATA    0
#define FIFO_MOCK    1

// Defines addresses configured on QSys (bar0)
#define PCIE_AVALONTOP  0x0000

// Defines addresses configured on QSys (bar2)
#define PCIE_CRA        0x0000

// Defines some CRA addresses
#define CRA_INTSTAREG   0x40

#define AVALONTOP_WADDR   0x10
#define AVALONTOP_RFLAG   0x10
#define AVALONTOP_WSTOP   0x14
#define AVALONTOP_GSZREF  0x18
#define AVALONTOP_GTSDEQ  0x1c
#define AVALONTOP_SETOFF  0x40

#define AVALONTOP_DOMOCK  0x08
#define AVALONTOP_MOCKBSY 0x08
#define AVALONTOP_MOCKEN  0x0c

#define DMA_BITS 32
#define DMA_BUF_WORDS (2*3*256)
#define DMA_BUF_SIZE (DMA_BUF_WORDS*sizeof(uint64_t))

#define DMA_MOCK_WORDS 8192
#define DMA_MOCK_SIZE (DMA_MOCK_WORDS*sizeof(uint64_t))

static int offsetArray[16] = {
    0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff,
    0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff, 0x7ff
};

static void *avalontop_base;

static uint8_t n_devices = 0;

static uint32_t epoch = 2;
static uint64_t *dma_ptr = NULL;
static dma_addr_t dma_handle;

static uint16_t *mock_ptr = NULL;
static dma_addr_t mock_handle;
static int mock_amount_read = 0;


// -------- Interrupt handler --------
static int irq_handler(unsigned irq, void *cookie_) {
    const uint32_t flag = ioread32(avalontop_base + AVALONTOP_RFLAG);
    const int irq_is_ours = (flag == epoch);

    rt_printk("pcie_interrupt_driver: got IRQ, flag=%d, is_ours=%d.\n", flag, irq_is_ours);

    if (likely(irq_is_ours)) {
        const int firstIndex = (flag % 2 == 0) ? 0 : DMA_BUF_WORDS/2;
        uint32_t regval;
        regval = ioread32(avalontop_base + AVALONTOP_GSZREF);
        rtf_put(FIFO_DATA, (void*)&regval, sizeof(regval));
        regval = ioread32(avalontop_base + AVALONTOP_GTSDEQ);
        rtf_put(FIFO_DATA, (void*)&regval, sizeof(regval));
        rtf_put(FIFO_DATA, (void*)&dma_ptr[firstIndex], DMA_BUF_SIZE/2);
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
    .name       = "pcie_interrupt",
    .id_table   = pci_ids,
    .probe      = pci_probe,
    .remove     = pci_remove,
};

static int pci_probe(struct pci_dev *dev, const struct pci_device_id *id) {
    unsigned long resource;
    int i, retval;

    if (++n_devices > 1)
        return -EOVERFLOW;

    retval = pci_enable_device(dev);

    if (retval) {
        rt_printk("pcie_interrupt_driver: ERROR: Unable to enable device: %d\n",retval);
        return retval;
    }
    else
        rt_printk("pcie_interrupt_driver: device enabled!\n");

    // Allow device to master the bus (required for DMA)
    pci_set_master(dev);

    // Set coherent DMA address limitation
    retval = pci_set_consistent_dma_mask(dev, DMA_BIT_MASK(DMA_BITS));
    if (retval) {
        rt_printk("pcie_interrupt_driver: ERROR: Unable to set DMA bit mask: %d\n", retval);
        return retval;
    }

    // Allocate a memory block suitable for coherent DMA
    dma_ptr = dma_alloc_coherent(&dev->dev, DMA_BUF_SIZE, &dma_handle, GFP_KERNEL);
    if (dma_ptr == NULL) {
        rt_printk("pcie_interrupt_driver: could not allocate memory for DMA\n");
        return -ENOMEM;
    }

    rt_printk("pcie_interrupt_driver: Allocated coherent memory: dma_handle=0x%x, ptr=%p\n", dma_handle, dma_ptr);

    mock_ptr = dma_alloc_coherent(&dev->dev, DMA_MOCK_SIZE, &mock_handle, GFP_KERNEL);
    if (mock_ptr == NULL) {
        rt_printk("pcie_interrupt_driver: could not allocate memory for (Mock) DMA\n");
        return -ENOMEM;
    }

    rt_printk("pcie_interrupt_driver: Allocated coherent memory: mock_handle=0x%x, ptr=%p\n", mock_handle, mock_ptr);

    // Gets a pointer to bar0
    resource = pci_resource_start(dev,0);
    avalontop_base = ioremap_nocache(resource + PCIE_AVALONTOP, 16);

    // Read vendor ID
    rt_printk("pcie_interrupt_driver: Found Vendor id: 0x%0.4x\n", dev->vendor);
    rt_printk("pcie_interrupt_driver: Found Device id: 0x%0.4x\n", dev->device);

    // Read IRQ Number
    rt_printk("pcie_interrupt_driver: Found IRQ: %d\n", dev->irq);

    // Request IRQ and install handler
    retval = rt_request_irq(dev->irq, irq_handler, NULL, 0);
    if (retval) {
        rt_printk("pcie_interrupt_driver: request_irq failed!\n");
        return retval;
    }

    rt_startup_irq(dev->irq);

    // Set offsets
    rt_printk("pcie_interrupt_driver: setting up OffsetSubtractor\n");
    for (i = 0; i < ARRAY_SIZE(offsetArray); i++) {
        rt_printk("pcie_interrupt_driver: offsetArray[%d] = 0x%03x;\n", i, offsetArray[i]);
        iowrite32(offsetArray[i], avalontop_base + AVALONTOP_SETOFF + 4*i);
    }

    rt_printk("pcie_interrupt_driver: enabling MockAD\n");
    iowrite32(1, avalontop_base + AVALONTOP_MOCKEN);

    rt_printk("pcie_interrupt_driver: enabling WindowDMA\n");
    iowrite32(dma_handle, avalontop_base + AVALONTOP_WADDR);

    return 0;
}

static void pci_remove(struct pci_dev *dev) {

    rt_release_irq(dev->irq);

    --n_devices;

    if (dma_ptr != NULL)
        dma_free_coherent(&dev->dev, DMA_BUF_SIZE, dma_ptr, dma_handle);

    if (mock_ptr != NULL)
        dma_free_coherent(&dev->dev, DMA_BUF_SIZE, mock_ptr, mock_handle);

    iounmap(avalontop_base);

    pci_set_drvdata(dev,NULL);
    rt_printk("pcie_interrupt_driver: Interrupt handler uninstalled.\n");
}

static int fifo_mock_handler (unsigned int fifo) {
    rt_printk("pcie_interrupt_driver: reading block from mock FIFO.\n");
    mock_amount_read += rtf_get(fifo, mock_ptr, DMA_MOCK_SIZE - mock_amount_read);

    if (mock_amount_read < DMA_MOCK_SIZE)
        return 0;

    if (unlikely(mock_amount_read > DMA_MOCK_SIZE)) {
        rt_printk("pcie_interrupt_driver: FATAL: mock buffer was overflown!\n");
        return -EOVERFLOW;
    }

    mock_amount_read -= DMA_MOCK_SIZE;

    while (ioread32(avalontop_base + AVALONTOP_MOCKBSY))
        rt_printk("pcie_interrupt_driver: waiting mock busy signal to cease\n");

    rt_printk("pcie_interrupt_driver: signaling to DMA controller that mock block is ready.\n");
    iowrite32(mock_handle, avalontop_base + AVALONTOP_DOMOCK);

    return 0;
}

/*******************************
 *  Driver Init/Exit Functions *
 *******************************/

module_param_array(offsetArray, int, NULL, 0);
MODULE_PARM_DESC(offsetArray, "DC offsets calibrated for each channel.");

static int __init pcie_interrupt_init(void) {
    int i, retval;

    for (i = 0; i < ARRAY_SIZE(offsetArray); i++) {
        if (offsetArray[i] < 0 || offsetArray[i] >= (1<<12)) {
            rt_printk("pcie_interrupt_driver: %d-th offset invalid: %d.\n", i, offsetArray[i]);
            return -EINVAL;
        }
    }

    rtf_create(FIFO_DATA, 16*MB);

    rtf_create(FIFO_MOCK, 32*MB);
    rtf_create_handler(FIFO_MOCK, fifo_mock_handler);

    // Register PCI Driver
    // IRQ is requested on pci_probe
    retval = pci_register_driver(&pci_driver);
    if (retval)
        rt_printk("pcie_interrupt_driver: ERROR: cannot register pci.\n");
    else
        rt_printk("pcie_interrupt_driver: pci driver registered.\n");

    return retval;
}

static void __exit pcie_interrupt_exit(void) {
    rtf_destroy(FIFO_MOCK);

    iowrite32(0, avalontop_base + AVALONTOP_WSTOP);
    iowrite32(0, avalontop_base + AVALONTOP_MOCKEN);

    rtf_destroy(FIFO_DATA);

    pci_unregister_driver(&pci_driver);
    rt_printk("pcie_interrupt_driver: pci driver unregistered.\n");
}

module_init(pcie_interrupt_init);
module_exit(pcie_interrupt_exit);
MODULE_LICENSE("GPL");
