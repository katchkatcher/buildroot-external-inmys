INMYS_BOARD_ID_VERSION = 1.0
INMYS_BOARD_ID_SITE = $(BR2_EXTERNAL_INMYS_PATH)/package/inmys-board-id/src
INMYS_BOARD_ID_SITE_METHOD = local
INMYS_BOARD_ID_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))