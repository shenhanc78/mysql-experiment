DDIR := $(shell pwd)
LLVM_INSTALL_BIN := $(DDIR)/llvm/install/bin
BASELINE_LLVM_INSTALL_BIN := $(DDIR)/llvm/install-baseline/bin

# upstream repo is: https://github.com/llvm/llvm-project.git
LLVM_REPO := https://github.com/llvm/llvm-project.git
LLVM_USE_GITHASH := 6db71b8f1418170324b49d20f1f7b3f7c5086066

PATH  := $(LLVM_INSTALL_BIN):$(PATH)
SHELL := env PATH=$(PATH) /bin/bash -eux -o pipefail
PROCESSOR_NUMBER := $(shell cat /proc/cpuinfo | grep -E "^processor\s+:\s+[0-9]+$$" | wc -l)
PARALLEL_LINK_JOBS := $(shell echo $$(( $(PROCESSOR_NUMBER) / 3)))

MYSQL_PACKAGE_NAME := mysql-boost-8.0.29.tar.gz
MYSQL_NAME := mysql-8.0.29
MYSQL_SOURCE := $(DDIR)/$(MYSQL_NAME)
DBT2_NAME := dbt2-0.37.50.16
DBT2_SOURCE := $(DDIR)/$(DBT2_NAME)

PROPELLER_INTRA_OPTS := --propeller_chain_split=true  --propeller_call_chain_clustering=true
PROPELLER_INTER_OPTS := --propeller_chain_split=true --propeller_forward_jump_distance=2048 --propeller_backward_jump_distance=1400 --propeller_call_chain_clustering=true --propeller_chain_split_threshold=256 --propeller_inter_function_ordering=true

# For fsafdo bootstrap
FSAFDO_OPT_0 := -g -fdebug-info-for-profiling -mllvm -enable-fs-discriminator=true -mllvm -disable-ra-fsprofile-loader=true -mllvm -disable-layout-fsprofile-loader=true -mllvm -disable-last-fsprofile-loader=true
# For fsafdo apply
FSAFDO_OPT_1 := -g -fdebug-info-for-profiling -mllvm -enable-fs-discriminator=true -mllvm -disable-ra-fsprofile-loader=false -mllvm -disable-layout-fsprofile-loader=false -mllvm -disable-last-fsprofile-loader=false -Wno-error=backend-plugin

BASELINE_FSAFDO_OPT_0 := -g -fdebug-info-for-profiling -mllvm -enable-fs-discriminator=true -mllvm -disable-ra-fsprofile-loader=true -mllvm -disable-layout-fsprofile-loader=true
# For fsafdo apply
BASELINE_FSAFDO_OPT_1 := -g -fdebug-info-for-profiling -mllvm -enable-fs-discriminator=true -mllvm -disable-ra-fsprofile-loader=false -mllvm -disable-layout-fsprofile-loader=false -Wno-error=backend-plugin

common_compiler_flags := -DDBUG_OFF -O3 -DNDEBUG -Qunused-arguments -funique-internal-linkage-names
common_linker_flags := -fuse-ld=lld -Wl,-z,keep-text-section-prefix -Wl,--build-id -Wl,--no-rosegment

gen_compiler_flags = -DCMAKE_C_FLAGS=$(1) -DCMAKE_CXX_FLAGS=$(1)
gen_linker_flags   = -DCMAKE_EXE_LINKER_FLAGS=$(1) -DCMAKE_SHARED_LINKER_FLAGS=$(1) -DCMAKE_MODULE_LINKER_FLAGS=$(1)
gen_build_flags = $(call gen_compiler_flags,"$(common_compiler_flags) $(1)") $(call gen_linker_flags,"$(common_linker_flags) $(2)")

COMMA := ,

# vanillaq is with -Wl,-q
# vanillal is with labels section
FLAVORS := vanilla vanillaq vanillal pgo_instrument pgolto pgolto_propeller pgolto_propeller_inter pgoltol pgoltoq vanilla_bolt vanilla_propeller vanilla_propeller_inter pgolto_bolt \
	fsafdo0 fsafdo fsafdo_mfs baseline_fsafdo0 baseline_fsafdo

include Makefile.bolt.inc

define build_mysql
	mkdir -p $(VARIANT_DIR)/build
	export PATH="$(1):$$PATH" ; \
	cd $(VARIANT_DIR)/build && cmake -G Ninja \
		-DWITH_BOOST=$(MYSQL_SOURCE)/boost/boost_1_77_0 \
		-DWITH_SSL=$(DDIR)/openssl_1_1_1-stable \
                -DCMAKE_INSTALL_PREFIX=$(VARIANT_DIR)/install \
                -DCMAKE_LINKER="lld" \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_COMPILER="$(1)/clang" \
                -DCMAKE_CXX_COMPILER="$(1)/clang++" \
		-DWITH_ROUTER=Off \
		-DWITH_UNIT_TESTS=Off \
		-DENABLED_PROFILING=Off \
                $(2) \
                $(MYSQL_SOURCE) && ninja install \
	|| { echo "*** build failed ***"; exit 1 ; }
	touch $@
endef

%: VARIANT_DIR = $(DDIR)/$(firstword $(subst /, ,$@))

llvm/llvm-project/README.md:
	mkdir -p llvm ; cd llvm ; git clone $(LLVM_REPO) llvm-project; \
	  cd llvm-project ; \
	  git checkout "$(LLVM_USE_GITHASH)"

llvm/install/bin/clang++: llvm/llvm-project/README.md
	mkdir -p llvm/build llvm/install
	cd llvm/build; \
	cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \
	  -DCMAKE_INSTALL_PREFIX=$(DDIR)/llvm/install \
	  -DCMAKE_C_COMPILER=clang \
	  -DCMAKE_CXX_COMPILER=clang++ \
	  -DCMAKE_ASM_COMPILER=clang \
	  -DLLVM_ENABLE_PROJECTS="compiler-rt;clang;llvm;lld;bolt" \
	  -DLLVM_OPTIMIZED_TABLEGEN=On \
	  -DLLVM_ENABLE_RTTI=On \
	  -DLLVM_TARGETS_TO_BUILD="X86" \
	  -DLLVM_BUILD_TESTS=Off \
	  -DLLVM_INCLUDE_TESTS=Off \
	  -DLLVM_PARALLEL_LINK_JOBS="$(PARALLEL_LINK_JOBS)" ../llvm-project/llvm ; \
	  ninja install

create_llvm_prof: llvm/install/bin/clang++
	./build_create_llvm_prof.sh "$(DDIR)/llvm/install"

packages/$(MYSQL_PACKAGE_NAME):
	echo "Please download $(MYSQL_PACKAGE_NAME) manually and put it under $(DDIR)/packages."
	exit 1

openssl_1_1_1-stable/.installed:
	git clone https://github.com/openssl/openssl.git openssl.git
	cd openssl.git ; \
	git checkout OpenSSL_1_1_1-stable ; \
	./config --prefix="$(DDIR)/$(shell dirname $@)" "--openssldir=$(DDIR)/$(shell dirname $@)/ssl" ; \
	make -j50 ; make -j50 install
	touch $@

$(MYSQL_NAME)/README: packages/${MYSQL_PACKAGE_NAME) packages/mysql.patch openssl_1_1_1-stable/.installed
	tar xzvf $<
	cd "$(VARIANT_DIR)" ; patch -p1 < "$(DDIR)/$(lastword $^)"
	touch $@

vanilla-mysql/install/bin/mysqld: $(MYSQL_NAME)/README llvm/install/bin/clang++
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin,-flto=thin))

vanillaq-mysql/install/bin/mysqld: $(MYSQL_NAME)/README llvm/install/bin/clang++
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin,-flto=thin -Wl$(COMMA)-q))

vanillal-mysql/install/bin/mysqld: $(MYSQL_NAME)/README llvm/install/bin/clang++
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin -fbasic-block-sections=labels,-flto=thin -Wl$(COMMA)--lto-basic-block-sections=labels))

baseline_fsafdo0-mysql/install/bin/mysqld: $(MYSQL_NAME)/README llvm/install-baseline/bin/clang++
	$(call build_mysql,$(BASELINE_LLVM_INSTALL_BIN),$(call gen_build_flags,$(BASELINE_FSAFDO_OPT_0) -flto=thin,-flto=thin))

fsafdo0-mysql/install/bin/mysqld: $(MYSQL_NAME)/README llvm/install/bin/clang++
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,$(FSAFDO_OPT_0) -flto=thin,-flto=thin))

baseline_fsafdo-mysql/install/bin/mysqld: baseline_fsafdo0-mysql/perf.fsafdo
	$(call build_mysql,$(BASELINE_LLVM_INSTALL_BIN),$(call gen_build_flags,-fprofile-sample-use=$(DDIR)/$< $(BASELINE_FSAFDO_OPT_1) -flto=thin,-flto=thin))

fsafdo-mysql/install/bin/mysqld: fsafdo0-mysql/perf.fsafdo
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-fprofile-sample-use=$(DDIR)/$< $(FSAFDO_OPT_1) -flto=thin,-flto=thin))


fsafdo_mfs-mysql/install/bin/mysqld: fsafdo0-mysql/perf.fsafdo
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-fsplit-machine-functions -fprofile-sample-use=$(DDIR)/$< $(FSAFDO_OPT_1) -flto=thin,-flto=thin))

baseline_create_llvm_prof:
	cp -f /google/data/ro/teams/autofdo/create_llvm_prof $@

baseline_fsafdo0-mysql/perf.fsafdo fsafdo0-mysql/perf.fsafdo: %fsafdo0-mysql/perf.fsafdo: %fsafdo0-mysql/perf.data %fsafdo0-mysql/install/bin/mysqld %create_llvm_prof
	./$*create_llvm_prof --profile=$< --binary=$(word 2,$^) --format=extbinary --out=$@

pgo_instrument-mysql/install/bin/mysqld: $(MYSQL_NAME)/README llvm/install/bin/clang++
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin,-flto=thin) -DFPROFILE_GENERATE=1 -DFPROFILE_DIR="$(VARIANT_DIR)/profile-data/%4m.profraw")

# run_loadtest "$(DBT2_SOURCE)" "$(VARIANT_DIR)/loadtest_output" 90 $(VARIANT_DIR)/install/lib ;
pgo_instrument-mysql/profile-data/default.profdata: pgo_instrument-mysql/setup
	rm -fr $(VARIANT_DIR)/profile-data
	"$(DDIR)/loadtest-funcs.sh" run_sysbench_loadtest "$(VARIANT_DIR)"
	cd $(VARIANT_DIR)/profile-data ; \
	$(LLVM_INSTALL_BIN)/llvm-profdata merge -output=$(DDIR)/$@ *.profraw ; \
	rm *.profraw

pgolto-mysql/install/bin/mysqld: pgo_instrument-mysql/profile-data/default.profdata
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin,-flto=thin) -DFPROFILE_USE=1 -DFPROFILE_DIR="$(DDIR)/$<")

pgoltol-mysql/install/bin/mysqld: pgo_instrument-mysql/profile-data/default.profdata
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin -fbasic-block-sections=labels,-flto=thin -Wl$(COMMA)--lto-basic-block-sections=labels) -DFPROFILE_USE=1 -DFPROFILE_DIR="$(DDIR)/$<")

pgoltoq-mysql/install/bin/mysqld: pgo_instrument-mysql/profile-data/default.profdata
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin,-flto=thin -Wl$(COMMA)-q) -DFPROFILE_USE=1 -DFPROFILE_DIR="$(DDIR)/$<")

to_ld_profile = $(shell echo $(1) | sed -Ee 's/cc_profile/ld_profile/')

# $1 is create_llvm_prof arguments
# $2 is tag, can be empty
define create_llvm_prof
	/usr/bin/time -v ./create_llvm_prof --format=propeller --binary="$<" --profile="$(word 2,$^)" \
	  $(1) \
	  --out="$(DDIR)/$@" \
	  --propeller_symorder="$(DDIR)/$(shell echo $@ | sed -Ee 's/cc_profile/ld_profile/')" \
	  2>&1 | tee "$(VARIANT_DIR)/create_llvm_prof$(2).log" \
	  || { rm -f "$(DDIR)/$@" "$(DDIR)/$(shell echo $@ | sed -Ee 's/cc_profile/ld_profile/')" ; exit 1 ; }
	echo "Done: $@"
	echo "Done: $(shell echo $@ | sed -Ee 's/cc_profile/ld_profile/')"
endef

$(foreach f,pgoltol vanillal,$(f)-mysql/cc_profile.txt): %-mysql/cc_profile.txt: %-mysql/install/bin/mysqld %-mysql/perf.data create_llvm_prof
	$(call create_llvm_prof,$(PROPELLER_INTRA_OPTS))

$(foreach f,pgoltol vanillal,$(f)-mysql/inter_cc_profile.txt): %-mysql/inter_cc_profile.txt: %-mysql/install/bin/mysqld %-mysql/perf.data create_llvm_prof
	$(call create_llvm_prof,$(PROPELLER_INTER_OPTS),-inter)

vanilla_propeller-mysql/install/bin/mysqld: vanillal-mysql/cc_profile.txt
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin -fbasic-block-sections=list=$(DDIR)/$<,-flto=thin -Wl$(COMMA)--lto-basic-block-sections=$(DDIR)/$< -Wl$(COMMAN)--no-warn-symbol-ordering -Wl$(COMMA)--symbol-ordering-file=$(call to_ld_profile,$(DDIR)/$<)))

vanilla_propeller_inter-mysql/install/bin/mysqld: vanillal-mysql/inter_cc_profile.txt
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin -fbasic-block-sections=list=$(DDIR)/$<,-flto=thin -Wl$(COMMA)--lto-basic-block-sections=$(DDIR)/$< -Wl$(COMMAN)--no-warn-symbol-ordering -Wl$(COMMA)--symbol-ordering-file=$(call to_ld_profile,$(DDIR)/$<)))

pgolto_propeller-mysql/install/bin/mysqld: \
	pgo_instrument-mysql/profile-data/default.profdata \
	pgoltol-mysql/cc_profile.txt
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin -fbasic-block-sections=list=$(DDIR)/$(word 2,$^),-flto=thin -Wl$(COMMA)--lto-basic-block-sections=$(DDIR)/$(word 2,$^) -Wl$(COMMAN)--no-warn-symbol-ordering -Wl$(COMMA)--symbol-ordering-file=$(call to_ld_profile,$(DDIR)/$(word 2,$^))) -DFPROFILE_USE=1 -DFPROFILE_DIR="$(DDIR)/$<")

pgolto_propeller_inter-mysql/install/bin/mysqld: \
	pgo_instrument-mysql/profile-data/default.profdata \
	pgoltol-mysql/inter_cc_profile.txt
	$(call build_mysql,$(LLVM_INSTALL_BIN),$(call gen_build_flags,-flto=thin -fbasic-block-sections=list=$(DDIR)/$(word 2,$^),-flto=thin -Wl$(COMMA)--lto-basic-block-sections=$(DDIR)/$(word 2,$^) -Wl$(COMMAN)--no-warn-symbol-ordering -Wl$(COMMA)--symbol-ordering-file=$(call to_ld_profile,$(DDIR)/$(word 2,$^))) -DFPROFILE_USE=1 -DFPROFILE_DIR="$(DDIR)/$<")

$(foreach f,vanillaq vanillal pgoltoq pgoltol fsafdo0 baseline_fsafdo0,$(f)-mysql/perf.data): %-mysql/perf.data: %-mysql/install/bin/mysqld %-mysql/setup
	"$(DDIR)/loadtest-funcs.sh" run_perf -o "$(DDIR)/$@" -- \
	  "$(DDIR)/loadtest-funcs.sh" run_sysbench_loadtest "$(VARIANT_DIR)" \
	|| { echo "*** loadtest failed ***" ; rm -f $(DDIR)/$@ ; exit 1; }

$(foreach f,$(FLAVORS),$(f)-mysql/setup): %-mysql/setup: %-mysql/install/bin/mysqld
	$(DDIR)/loadtest-funcs.sh setup_mysql "$(VARIANT_DIR)" 2>&1 | tee $(DDIR)/$@

$(foreach f,$(FLAVORS),$(f)-mysql/sysbench): %-mysql/sysbench: %-mysql/install/bin/mysqld %-mysql/setup
	$(DDIR)/loadtest-funcs.sh run_sysbench_benchmark $(VARIANT_DIR) 5 && touch $(DDIR)/$@

$(DBT2_NAME)/README-MYSQL: packages/$(DBT2_NAME).tar.gz packages/dbt2.patch
	tar xzvf $<
	patch -p1 < $(lastword $^)
	touch $@

dbt2-tool/bin/datagen dbt2-tool/bin/driver &: $(DBT2_SOURCE)/Makefile.in
	cd $(DBT2_SOURCE); \
	make distclean ; \
	$(DBT2_SOURCE)/configure --prefix=$(DDIR)/dbt2-tool \
		--with-mysql=$(DDIR)/vanilla-mysql/install ; \
	make -j20 install

dbt2-tool/data/warehouse.data: dbt2-tool/bin/datagen
	rm -fr dbt2-tool/data
	mkdir -p dbt2-tool/data
	$< -w 30 -d dbt2-tool/data --mysql
	cd dbt2-tool/data ; \
	mapfile -t datafiles < <(find . -name "*.data" -type f) ; \
	for d in "$${datafiles[@]}" ; do \
		mv $$d $${d}.origin ; \
		iconv -f iso8859-1 -t utf-8 $${d}.origin -o $$d ; \
		rm $${d}.origin ; \
	done

define A_vs_B
$(1)-vs-$(2): $(1)-mysql/sysbench $(2)-mysql/sysbench t-test
	$(DDIR)/loadtest-funcs.sh sysbench_compare $(1)-mysql $(2)-mysql
endef

$(eval $(call A_vs_B,baseline_fsafdo,fsafdo))
$(eval $(call A_vs_B,fsafdo,fsafdo_mfs))
$(eval $(call A_vs_B,pgolto,pgolto_bolt))
$(eval $(call A_vs_B,pgolto,pgolto_propeller))
$(eval $(call A_vs_B,pgolto,pgolto_propeller_inter))
$(eval $(call A_vs_B,pgolto_bolt,pgolto_propeller))
$(eval $(call A_vs_B,pgolto_bolt,pgolto_propeller_inter))
$(eval $(call A_vs_B,pgolto_propeller,pgolto_propeller_inter))
$(eval $(call A_vs_B,vanilla,pgolto))
$(eval $(call A_vs_B,vanilla,vanilla_bolt))
$(eval $(call A_vs_B,vanilla,vanilla_propeller))
$(eval $(call A_vs_B,vanilla,vanilla_propeller_inter))
$(eval $(call A_vs_B,vanilla_bolt,vanilla_propeller))
$(eval $(call A_vs_B,vanilla_bolt,vanilla_propeller_inter))
$(eval $(call A_vs_B,vanilla_propeller,vanilla_propeller_inter))

t-test: t-test.cc llvm/install/bin/clang++
	llvm/install/bin/clang++ --std=c++17 -I$(MYSQL_SOURCE)/boost/boost_1_77_0 -O2 $< -o $@

data_to_spreadsheet:
	if [[ ! -d "/google/src/cloud/$(USER)/$(CITC_WORKSPACE)/google3" ]]; \
	then \
		echo "No access to google3 direcctory found, not inside google? or gcert expired?" ; exit 1 ; \
	fi
	cd /google/src/cloud/shenhan/clean/google3 ; \
	blaze build -c opt --symlink_prefix=$(DDIR)/blaze-build/ //devtools/crosstool/propeller/tools:$@
	cp -fv blaze-build/bin/devtools/crosstool/propeller/tools/data_to_spreadsheet .

# vanilla-vs-vanilla_bolt vanilla-vs-vanilla_propeller vanilla-vs-vanilla_propeller_inter vanilla_bolt-vs-vanilla_propeller vanilla_bolt-vs-vanilla_propeller_inter vanilla_propeller-vs-vanilla_propeller_inter

spreadsheet.data: pgolto-vs-pgolto_propeller pgolto-vs-pgolto_propeller_inter pgolto-vs-pgolto_bolt pgolto_bolt-vs-pgolto_propeller pgolto_bolt-vs-pgolto_propeller_inter pgolto_propeller-vs-pgolto_propeller_inter data_to_spreadsheet
	rm -f $@
	./gen-spreadsheet-data.sh \
	  pgolto-vs-pgolto_propeller pgolto-vs-pgolto_propeller_inter pgolto-vs-pgolto_bolt pgolto_bolt-vs-pgolto_propeller pgolto_bolt-vs-pgolto_propeller_inter pgolto_propeller-vs-pgolto_propeller_inter 2>&1 | tee -a $@

# only delete this target to generate a new spreadsheet
spreadsheet.id:
	if ./data_to_spreadsheet --data=$< 2>&1 | tee spreadsheet.id.tmp ; then \
		sed -nEe 's!^Created spreadsheet: https://docs.google.com/spreadsheets/d/([a-zA-Z0-9_-]+)/edit#gid=.*$$!\1!p' \
			spreadsheet.id.tmp | tee $@ ; \
	else \
		rm -f $@ ; \
	fi
	rm -f spreadsheet.id.tmp

spreadsheet: spreadsheet.id spreadsheet.data
	if ! ./data_to_spreadsheet --data=spreadsheet.data --update-spreadsheet="$(shell cat $<)" 2>&1 | tee $@ ; then \
		rm $@ ; \
	fi

clean:
	rm -fr $(foreach f,$(FLAVORS),$(f)-mysql)
	rm -f t-test llvm-bolt perf2bolt
	rm -fr llvm/build llvm/install llvm/install-baseline llvm/build-baseline llvm/*.log llvm/bolt-build
	rm -fr llvm/llvm-project-baseline
	rm -fr $(DBT2_SOURCE) $(MYSQL_SOURCE)
	rm -f create_llvm_prof
	rm -f baseline_create_llvm_prof
	rm -f spreadsheet.data
	rm -f data_to_spreadsheet
	rm -fr blaze-build/
