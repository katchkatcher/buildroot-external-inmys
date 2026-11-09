// SPDX-License-Identifier: GPL-2.0
/*
 * Board ID driver for NMS-SM-RK3568.
 * Reads 3 strap GPIOs (board-id-gpios, MSB first) and exposes the result
 * in dmesg and sysfs.
 */
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/sysfs.h>
#include <linux/of.h>

#define BOARD_ID_NGPIOS 3

struct board_id {
	u8 bits[BOARD_ID_NGPIOS];	/* bits[0] = MSB */
	unsigned int id;
};

static const struct {
	unsigned int id;
	const char *name;
} board_id_table[] = {
	{ 4, "v4" },	/* A4=1, C7=0, C4=0 (R36 not fitted, R103/R104 fitted) */
};

static const char *board_id_name(unsigned int id)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(board_id_table); i++)
		if (board_id_table[i].id == id)
			return board_id_table[i].name;
	return "unknown";
}

static ssize_t board_id_show(struct device *dev,
			     struct device_attribute *attr, char *buf)
{
	struct board_id *b = dev_get_drvdata(dev);

	return sysfs_emit(buf, "%u\n", b->id);
}
static DEVICE_ATTR_RO(board_id);

static ssize_t board_id_bits_show(struct device *dev,
				  struct device_attribute *attr, char *buf)
{
	struct board_id *b = dev_get_drvdata(dev);

	return sysfs_emit(buf, "%u%u%u\n", b->bits[0], b->bits[1], b->bits[2]);
}
static DEVICE_ATTR_RO(board_id_bits);

static ssize_t hw_version_show(struct device *dev,
			       struct device_attribute *attr, char *buf)
{
	struct board_id *b = dev_get_drvdata(dev);

	return sysfs_emit(buf, "%s\n", board_id_name(b->id));
}
static DEVICE_ATTR_RO(hw_version);

static struct attribute *board_id_attrs[] = {
	&dev_attr_board_id.attr,
	&dev_attr_board_id_bits.attr,
	&dev_attr_hw_version.attr,
	NULL,
};
ATTRIBUTE_GROUPS(board_id);

static int board_id_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct gpio_descs *descs;
	struct board_id *b;
	int i, val;

	b = devm_kzalloc(dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;

	descs = devm_gpiod_get_array(dev, "board-id", GPIOD_IN);
	if (IS_ERR(descs))
		return dev_err_probe(dev, PTR_ERR(descs),
				     "cannot get board-id-gpios\n");
	if (descs->ndescs != BOARD_ID_NGPIOS)
		return dev_err_probe(dev, -EINVAL,
				     "expected %d gpios, got %u\n",
				     BOARD_ID_NGPIOS, descs->ndescs);

	/* let the internal pull-up settle after pinctrl default state */
	usleep_range(1000, 2000);

	for (i = 0; i < BOARD_ID_NGPIOS; i++) {
		val = gpiod_get_value_cansleep(descs->desc[i]);
		if (val < 0)
			return dev_err_probe(dev, val, "read gpio %d failed\n", i);
		b->bits[i] = !!val;
		b->id = (b->id << 1) | b->bits[i];
	}

	platform_set_drvdata(pdev, b);

	dev_info(dev, "GPIO3_A4/C7/C4 = %u/%u/%u -> board_id=%u, hw version %s\n",
		 b->bits[0], b->bits[1], b->bits[2], b->id,
		 board_id_name(b->id));
	return 0;
}

static const struct of_device_id board_id_of_match[] = {
	{ .compatible = "inmys,board-id" },
	{ }
};
MODULE_DEVICE_TABLE(of, board_id_of_match);

static struct platform_driver board_id_driver = {
	.probe = board_id_probe,
	.driver = {
		.name = "inmys-board-id",
		.of_match_table = board_id_of_match,
		.dev_groups = board_id_groups,
	},
};
module_platform_driver(board_id_driver);

MODULE_DESCRIPTION("INMYS NMS-SM-RK3568 board ID reader");
MODULE_LICENSE("GPL");
