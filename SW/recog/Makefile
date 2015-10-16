
# Assume the source tree is where the running kernel was built
# You should set KERNELDIR in the environment if it's elsewhere
	KERNELDIR ?= /lib/modules/$(shell uname -r)/build
# The current directory is passed to sub-makes as argument
	PWD := $(shell pwd)
	EXTRA_CFLAGS := -I$(src) -I/usr/realtime/include -std=gnu1x -Wno-declaration-after-statement -march=native -msse -mmmx -msse2 -mavx -Ofast
	KBUILD_EXTRA_SYMBOLS := /usr/realtime/modules/Module.symvers

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions modules.order Module.symvers

obj-m := gymnort_recog.o
