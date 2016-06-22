#

.DEFAULT: subdirs

SUBDIRS = packer

subdirs: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

