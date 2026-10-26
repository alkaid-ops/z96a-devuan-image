# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_EXYNOS) += \
	exynos5422-odroidxu4-hktft-cs-ogst.dtbo \
	exynos5422-odroidxu4-hktft32.dtbo \
	exynos5422-odroidxu4-hktft35.dtbo \
	exynos5422-odroidxu4-i2c0.dtbo \
	exynos5422-odroidxu4-i2c1.dtbo \
	exynos5422-odroidxu4-spidev0.dtbo \
	exynos5422-odroidxu4-sx865x-i2c1.dtbo \
	exynos5422-odroidxu4-uart0.dtbo

dtbo-$(CONFIG_ARCH_SUNXI) += \
	sunxi-i2c0.dtbo \
	sunxi-i2c1.dtbo \
	sunxi-i2c2.dtbo \
	sunxi-spi-add-cs1.dtbo \
	sunxi-spi-jedec-nor.dtbo \
	sunxi-spi-spidev.dtbo \
	sunxi-uart1.dtbo \
	sunxi-uart2.dtbo \
	sunxi-uart3.dtbo \
	sunxi-ir-tx.dtbo \
	sunxi-overclock.dtbo \
	sunxi-usb-host-mode.dtbo \
	sunxi-usb-otg-mode.dtbo \
	sunxi-usb-peripheral-mode.dtbo

targets += dtbs dtbs_install
targets += $(dtbo-y)

always-y	:= $(dtbo-y)
clean-files	:= *.dtbo
