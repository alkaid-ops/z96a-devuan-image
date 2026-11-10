.ONESHELL:
.SILENT:
.PHONY: clean list

# header
HEADER=./scripts/.header

# menu
MENU=./lib/dialog/menu
GMENU=./lib/dialog/general
CONF=./lib/dialog/config
DIALOGRC=$(shell cp -f lib/dialog/dialogrc ~/.dialogrc)

# misc
RFS=./scripts/rootfs
RFSX=./scripts/rootfs-extra
ROOTFS=sudo ./scripts/rootfs
CLN=./scripts/clean
CLEAN=sudo ./scripts/clean

# purge
PURGE=$(shell sudo rm -fdr sources; if [ -d .cache ]; then sudo rm -f .cache/git_*; fi)
PURGEALL=$(shell sudo rm -fdr sources output; if [ -d .cache ]; then sudo rm -f .cache/git_*; fi)
PURGELOG=$(shell sudo rm -fdr output/logs)

# logger
RIT=./scripts/runit
LIT=./scripts/loggit

# uboot and linux
XUBOOT=./scripts/uboot
UBOOT=sudo ./scripts/uboot
DTCLIST=./scripts/dtclist
XKERNEL=./scripts/linux
KERNEL=sudo ./scripts/linux

# image
IMG=./scripts/stage1
IMAGE=sudo --preserve-env=RELEASE_TAG,RELEASE_CHANNEL,CHROOT_CACHE,CHROOT_CACHE_DIR,CHROOT_CACHE_KEY,Z96A_DEBUG_PARTITION,Z96A_SSH_KEY,Z96A_ROOT_PASSWORD,Z96A_WIFI_SSID,Z96A_WIFI_PASSKEY ./scripts/stage1
STG2=./scripts/stage2
XUSB=./scripts/usbboot
USBBOOT=sudo ./scripts/usbboot

# dependencies
CCOMPILE=./scripts/.ccompile
NCOMPILE=./scripts/.ncompile

# miscellaneous
CHECK=./scripts/.check

# BOARDS
# Phase 2 M2: board.txt is generated from config/<board>.toml. The build
# refuses to start when the TOML and lib/boards/<board> disagree, so a stale
# hand-edited copy can never silently build a different image.
define board_setup
	@rm -f board.txt 2>/dev/null || sudo rm -f board.txt; \
	if [ -x "boards/$(board)/tools/gen-board-config.sh" ]; then \
		boards/$(board)/tools/gen-board-config.sh --check >/dev/null || { \
			echo "ERROR: config/$(board).toml and lib/boards/$(board) disagree." >&2; \
			echo "       run: make board-config board=$(board)" >&2; \
			exit 1; \
		}; \
	fi; \
	if [ -f "lib/boards/$(board)" ]; then \
		cp "lib/boards/$(board)" board.txt 2>/dev/null || sudo cp "lib/boards/$(board)" board.txt; \
	fi
endef

ifdef board
include lib/boards/${board}
endif

define create_config
	@chmod +x ${CONF}
	@${CONF}
endef

define build_uboot
	$(board_setup)
	@chmod +x ${XUBOOT}
	@${UBOOT}
endef

define build_kernel
	$(board_setup)
	@chmod +x ${DTCLIST}
	@chmod +x ${XKERNEL}
	@${DTCLIST}
	@${KERNEL}
endef

define build_image
	$(board_setup)
	@chmod +x ${IMG}
	@chmod +x ${STG2}
	@${IMAGE}
endef

define create_rootfs
	$(board_setup)
	@chmod +x ${RFS}
	@chmod +x ${RFSX}
	@${ROOTFS}
endef 

define build_usbboot
	$(board_setup)
	@chmod +x ${XUSB}
	@${USBBOOT}
endef

# USAGE
help:
	@echo ""
	@${HEADER}
	@echo ""
	@echo "\e[1;37mCommand List:\e[0m"
	@echo "  make ccompile\t\t\tInstall x86_64 dependencies"
	@echo "  make ncompile\t\t\tInstall aarch64 dependencies"
	@echo "  make config\t\t\tCreate user data file"
	@echo "  make menu\t\t\tMenu interface"
	@echo "  make clean\t\t\tClean up rootfs / image errors"
	@echo "  make purge\t\t\tRemove sources"
	@echo "  make purge-log\t\tRemove all logs"
	@echo "  make purge-all\t\tRemove logs, output and sources"
	@echo "  make board-config board=xxxx\tRegenerate config from config/<board>.toml"
	@echo "  make preflight board=xxxx\tValidate packaging inputs"
	@echo "  make check\t\t\tLatest revision of selected branch"
	@echo ""
	@echo "  make list\t\t\tList boards"
	@echo "  make uboot board=xxxx\t\tBuild u-boot package"
	@echo "  make kernel board=xxxx\tBuild linux kernel package"
	@echo "  make rootfs board=xxxx\tCreate rootfs tarball"
	@echo "  make image board=xxxx\t\tMake bootable image"
	@echo "  make usbboot board=xxxx\tMake bootable usb SDCARD image"
	@echo "  make all board=xxxx\t\tFeeling lucky?"
	@echo ""
	@echo "For details consult the \e[1;37mREADME.md\e[0m file"
	@echo

# DEPENDENCIES
ccompile:
	# X86_64 dependencies:
	@chmod +x ${CCOMPILE}
	@${CCOMPILE}

ncompile:
	# Aarch64 dependencies:
	@chmod +x ${NCOMPILE}
	@${NCOMPILE}

# USER DATA
config:
ifdef edit
	@if [ -f ${edit}.txt ]; then nano ${edit}.txt; else echo "${edit}.txt: file not found"; fi
	exit
endif
	$(call create_config)

# MENU
menu:
	@chmod +x ${MENU}
	@chmod +x ${GMENU}
	@chmod +x ${RIT}
	@chmod +x ${LIT}
	@${MENU}

# U-BOOT
uboot:
	@rm -f ignore.txt
ifdef build
	@echo 'BUILD_VERSION="$(build)"' >> ignore.txt
endif
ifdef compiler
	@echo 'COMPILER="$(compiler)"' >> ignore.txt
endif
ifdef cores
	@echo 'CORES="$(cores)"' >> ignore.txt
endif
ifdef menuconfig
	@echo 'MENUCONFIG="$(menuconfig)"' >> ignore.txt
endif
ifdef version
	@echo 'UBOOT_VERSION="$(version)"' >> ignore.txt
endif
ifdef verbose
	@echo 'VERBOSE="$(verbose)"' >> ignore.txt
endif
ifdef precompiled
	@echo 'PRECOMPILED_UBOOT="$(precompiled)"' >> ignore.txt
endif
ifdef force
	@echo 'FORCE_VERSION="$(force)"' >> ignore.txt
endif
	$(call build_uboot)

# KERNEL
kernel:
	@rm -f ignore.txt
ifdef build
	@echo 'BUILD_VERSION="$(build)"' >> ignore.txt
endif
ifdef compiler
	@echo 'COMPILER="$(compiler)"' >> ignore.txt
endif
ifdef cores
	@echo 'CORES="$(cores)"' >> ignore.txt
endif
ifdef extra_wifi
	@echo 'EXTRA_WIFI="$(extra_wifi)"' >> ignore.txt
endif
ifdef menuconfig
	@echo 'MENUCONFIG="$(menuconfig)"' >> ignore.txt
endif
ifdef myconfig
	@echo 'CUSTOM_DEFCONFIG="1"' >> ignore.txt
	@echo 'MYCONFIG="${myconfig}_defconfig"' >> ignore.txt
endif
ifdef verbose
	@echo 'VERBOSE="$(verbose)"' >> ignore.txt
endif
ifdef version
	@echo 'VERSION="$(version)"' >> ignore.txt
endif
ifdef git
	@echo 'FORCE_GIT="$(git)"' >> ignore.txt
endif
ifdef force
	@echo 'FORCE_VERSION="$(force)"' >> ignore.txt
endif
ifdef legacy
	@echo 'FORCE_LEGACY_PACKAGING="$(legacy)"' >> ignore.txt
endif
ifdef patching
	@echo 'LINUX_PATCHING="$(patching)"' >> ignore.txt
endif
	$(call build_kernel)

# ROOTFS
rootfs:
# edit user data file
ifdef distro
	@$(shell sed -i "s/^DISTRO=.*/DISTRO="'"${distro}"'"/" userdata.txt)
endif
ifdef minimal
	@$(shell sed -i "s/^MINIMAL_ROOTFS=.*/MINIMAL_ROOTFS="'"${minimal}"'"/" custom.txt)
endif
ifdef release
	@$(shell sed -i "s/^DISTRO_VERSION=.*/DISTRO_VERSION="'"${release}"'"/" userdata.txt)
endif
ifdef verbose
	@$(shell sed -i "s/^VERBOSE=.*/VERBOSE="'"${verbose}"'"/" userdata.txt)
endif
	$(call create_rootfs)

# IMAGE
image:
# edit user data file
ifdef distro
	@$(shell sed -i "s/^DISTRO=.*/DISTRO="'"${distro}"'"/" userdata.txt)
endif
ifdef minimal
	@$(shell sed -i "s/^MINIMAL_ROOTFS=.*/MINIMAL_ROOTFS="'"${minimal}"'"/" custom.txt)
endif
ifdef release
	@$(shell sed -i "s/^DISTRO_VERSION=.*/DISTRO_VERSION="'"${release}"'"/" userdata.txt)
endif
ifdef verbose
	@$(shell sed -i "s/^VERBOSE=.*/VERBOSE="'"${verbose}"'"/" userdata.txt)
endif
	$(call build_image)

# ALL
all:
	$(call build_uboot)
	$(call build_kernel)
	$(call create_rootfs)
	$(call build_image)

usbboot:
	$(call build_usbboot)

# MISCELLANEOUS
# Regenerate board variables from config/<board>.toml (phase 2 single source).
board-config:
	@if [ -x "boards/$(board)/tools/gen-board-config.sh" ]; then \
		boards/$(board)/tools/gen-board-config.sh --write; \
	else \
		echo "No config generator for board '$(board)'"; \
	fi

# Validate packaging inputs before a build (board-specific when available).
preflight:
	@if [ -n "$(board)" ] && [ -x "boards/$(board)/tools/preflight.sh" ]; then \
		boards/$(board)/tools/preflight.sh; \
	else \
		echo "No preflight script for board '$(board)'"; \
	fi

check:
	@chmod +x ${CHECK}
	@${CHECK}

reset:
	@$(shell sed -i "s/^BUILD_VERSION=.*/BUILD_VERSION="'"1"'"/" userdata.txt)
	@$(shell sed -i "s/^CUSTOM_DEFCONFIG=.*/CUSTOM_DEFCONFIG="'"0"'"/" userdata.txt)
	@$(shell sed -i "s/^MENUCONFIG=.*/MENUCONFIG="'"0"'"/" userdata.txt)
	@$(shell sed -i "s/^MINIMAL_ROOTFS=.*/MINIMAL_ROOTFS="'"false"'"/" custom.txt)
	@$(shell sed -i "s/^MYCONFIG=.*/MYCONFIG="'"_defconfig"'"/" userdata.txt)
	@$(shell sed -i "s/^VERBOSE=.*/VERBOSE="'"0"'"/" userdata.txt)

list:
	# Boards
	@ls lib/boards/

dialogrc:
	@${DIALOGRC}

clean:
	@chmod +x ${CLN}
	@${CLEAN}

purge:
	# Removing sources
	@${PURGE}

purge-all:
	# Removing logs, output and sources
	@${PURGEALL}

purge-log:
	# Removing logs
	@${PURGELOG}
