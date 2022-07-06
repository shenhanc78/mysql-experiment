llvm/install/bin/llvm-bolt: llvm/install/bin/clang++

llvm/install/bin/perf2bolt: llvm/install/bin/clang++

perf2bolt llvm-bolt: %: llvm/install/bin/%
	ln -sf $(DDIR)/$< $@

$(foreach f,vanillaq vanillal pgoltoq,$(f)-mysql/data.yaml): %-mysql/data.yaml: perf2bolt %-mysql/perf.data %-mysql/install/bin/mysqld
	/usr/bin/time -v ./$< "$(DDIR)/$(lastword $^)" -p "$(word 2,$^)" -o "$(VARIANT_DIR)/data.fdata" -w "$(VARIANT_DIR)/data.yaml" 2>&1 | tee $(VARIANT_DIR)/perf2bolt.log

# removed "-split-eh", which may cause error: "<unknown>:0: error: Cannot represent a difference across sections"
$(foreach f,vanillaq pgoltoq,$(f)-mysql/install/bin/mysqld_bolt): %-mysql/install/bin/mysqld_bolt: llvm-bolt %-mysql/install/bin/mysqld %-mysql/data.yaml
	/usr/bin/time -v ./$< "$(DDIR)/$(word 2,$^)" -o "$(DDIR)/$@" -b "$(lastword $^)" \
	  -reorder-blocks=ext-tsp -reorder-functions=hfsort -split-functions=3 \
	  -split-all-cold -inline-small-functions -simplify-rodata-loads -plt=hot \
	  -dyno-stats 2>&1 | tee $(VARIANT_DIR)/llvm-bolt.log

$(foreach f,vanilla pgolto,$(f)_bolt-mysql/install/bin/mysqld): %_bolt-mysql/install/bin/mysqld: %q-mysql/install/bin/mysqld_bolt
	rsync -av $*q-mysql/install ./$*_bolt-mysql/
	cp $< $@
