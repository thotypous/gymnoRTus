#include <linux/module.h>
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/errno.h>
#include <rtai.h>
#include <rtai_sched.h>
#include <rtai_fifos.h>

#define KB  1024
#define MB  1024*KB

#define FIFO_MOCK    1

// Defines addresses configured on QSys (bar0)
#define PCIE_AVALONTOP  0x0000

// Defines addresses configured on QSys (bar2)
#define PCIE_CRA        0x0000

// Defines some CRA addresses
#define CRA_INTSTAREG   0x40

// Defines for the AvalonTop Interface
#define AVALONTOP_DOMOCK  0x08
#define AVALONTOP_MOCKBSY 0x08
#define AVALONTOP_MOCKEN  0x0c

#define DMA_BITS 32
#define DMA_MOCK_WORDS 8192  // Same as MockADBufSize (SysConfig.bsv)
#define DMA_MOCK_SIZE (DMA_MOCK_WORDS*sizeof(uint64_t))

static void *avalontop_base;

static struct pci_dev *probed_pci_dev = NULL;

static uint16_t *mock_ptr = NULL;
static dma_addr_t mock_handle;
static int mock_amount_read = 0;


static struct pci_device_id pci_ids[] = {
    { PCI_DEVICE(0x1172, 0x0de4), },
    { 0, }
};
MODULE_DEVICE_TABLE(pci, pci_ids);

static int pci_probe(struct pci_dev *dev, const struct pci_device_id *id);
static void pci_remove(struct pci_dev *dev);

static struct pci_driver pci_driver = {
    .name       = "gymnort_mockad",
    .id_table   = pci_ids,
    .probe      = pci_probe,
    .remove     = pci_remove,
};

static int pci_probe(struct pci_dev *dev, const struct pci_device_id *id) {
    unsigned long resource;
    int retval;

    if(unlikely(probed_pci_dev != NULL))
        return -EOVERFLOW;
    probed_pci_dev = dev;

    retval = pci_enable_device(dev);

    if(retval) {
        rt_printk("gymnort_mockad: ERROR: Unable to enable device: %d\n",retval);
        return retval;
    }
    else
        rt_printk("gymnort_mockad: device enabled!\n");

    // Allow device to master the bus (required for DMA)
    pci_set_master(dev);

    // Set coherent DMA address limitation
    retval = pci_set_consistent_dma_mask(dev, DMA_BIT_MASK(DMA_BITS));
    if(retval) {
        rt_printk("gymnort_mockad: ERROR: Unable to set DMA bit mask: %d\n", retval);
        return retval;
    }

    mock_ptr = dma_alloc_coherent(&dev->dev, DMA_MOCK_SIZE, &mock_handle, GFP_KERNEL);
    if(mock_ptr == NULL) {
        rt_printk("gymnort_mockad: could not allocate memory for MockAD DMA\n");
        return -ENOMEM;
    }

    rt_printk("gymnort_mockad: Allocated coherent memory: mock_handle=0x%x, ptr=%p\n", mock_handle, mock_ptr);

    // Gets a pointer to bar0
    resource = pci_resource_start(dev,0);
    avalontop_base = ioremap_nocache(resource + PCIE_AVALONTOP, 16);

    // Read vendor ID
    rt_printk("gymnort_mockad: Found Vendor id: 0x%0.4x\n", dev->vendor);
    rt_printk("gymnort_mockad: Found Device id: 0x%0.4x\n", dev->device);

    iowrite32(1, avalontop_base + AVALONTOP_MOCKEN);

    return 0;
}

static void pci_remove(struct pci_dev *dev) {
    pci_set_drvdata(dev,NULL);
}

static int fifo_mock_handler(unsigned int fifo) {
    rt_printk("gymnort_mockad: waiting MockDMA to be ready.\n");
    while (ioread32(avalontop_base + AVALONTOP_MOCKBSY));

    rt_printk("gymnort_mockad: reading block from mock FIFO.\n");
    mock_amount_read += rtf_get(fifo, mock_ptr, DMA_MOCK_SIZE - mock_amount_read);

    if (mock_amount_read < DMA_MOCK_SIZE)
        return 0;

    if (unlikely(mock_amount_read > DMA_MOCK_SIZE)) {
        rt_printk("gymnort_mockad: FATAL: mock buffer was overflown!\n");
        return -EOVERFLOW;
    }

    mock_amount_read -= DMA_MOCK_SIZE;

    rt_printk("gymnort_mockad: signaling to DMA controller that mock block is ready.\n");
    iowrite32(mock_handle, avalontop_base + AVALONTOP_DOMOCK);

    return 0;
}

/*******************************
 *  Driver Init/Exit Functions *
 *******************************/

static int __init m_init(void) {
    int retval;

    rtf_create(FIFO_MOCK, 16*MB);

    // Register PCI Driver
    retval = pci_register_driver(&pci_driver);
    if (retval)
        rt_printk("gymnort_mockad: ERROR: cannot register pci.\n");
    else
        rt_printk("gymnort_mockad: pci driver registered.\n");

    rtf_create_handler(FIFO_MOCK, fifo_mock_handler);

    // Please pretend you have not seen the code below.
    // This allows us to register another pci driver (located in
    // another module) which accesses the same pci device. (1)
    pci_unregister_driver(&pci_driver);

    return retval;
}

static void __exit m_exit(void) {
    rtf_destroy(FIFO_MOCK);
    iowrite32(0, avalontop_base + AVALONTOP_MOCKEN);

    if(probed_pci_dev != NULL) {
        // This should be in pci_remove instead of here.
        // See comment (1) above.
        if(mock_ptr != NULL)
            dma_free_coherent(&probed_pci_dev->dev, DMA_MOCK_SIZE, mock_ptr, mock_handle);
        iounmap(avalontop_base);
    }

    rt_printk("gymnort_mockad: pci driver unregistered.\n");
}

module_init(m_init);
module_exit(m_exit);
MODULE_LICENSE("GPL");
