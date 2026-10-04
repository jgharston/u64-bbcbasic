# U64 BBC BASIC -- BBC BASIC 3.10 for the Ultimate 64 / C64 Ultimate
#
# make            build both cartridges in build/
# make compare-core   check the unpatched BASIC 3.10 against Ivo's reference
# make e2e        end-to-end tests through c64bridge (tests/e2e/README.md)
# make vice       run the EasyFlash cartridge in VICE
# make deploy     upload the cartridges to the Ultimates in .env

-include .env

comma    := ,
space    := $(subst ,, )

MADS     ?= mads
PYTHON   ?= python3
X64      ?= x64sc
MKDIR     = mkdir -p
BUILD     = build
NAME      = u64bbc

BASICLIB  = lib/bbc-basic
BASICSRC  = $(BASICLIB)/basic.s $(BASICLIB)/vars.s
BASICDIR  = $(BUILD)/basic

MOS_SRCS  = $(wildcard src/mos/*.s)
GEN       = $(BUILD)/gen/tables.s

ULTIP1   ?= <set_ULTIP1_in_.env>
ULTPATH   = /Temp/

CRTS      = $(BUILD)/$(NAME)-tmb.crt $(BUILD)/$(NAME)-ef.crt
CFGS      = $(CRTS:.crt=.cfg)

.PHONY: all clean compare-core e2e e2e-vice e2e-u64 vice deploy check-deploy checkcfg

all: $(CRTS) $(CFGS)

# --- BBC BASIC 3.10 for $8000, from Ivo van Poorten's source + our target

$(BASICDIR)/basic.s: $(BASICSRC) src/basic/u64-target.patch
	@$(MKDIR) $(BASICDIR)
	cp $(BASICSRC) $(BASICDIR)/
	patch -s -d $(BASICDIR) -p1 < src/basic/u64-target.patch

$(BUILD)/basic.rom: $(BASICDIR)/basic.s
	$(MADS) -d:BUILD_U64_BASIC310=1 -l:$(BUILD)/basic.lst -o:$@ $< >/dev/null

# --- MOS bank 0, one per cartridge type

$(GEN): tools/gentables.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< $@

# banks 0 and 2 in one assembly (src/mos/cart.s): 32K, bank 0 then bank 2
$(BUILD)/mos-ef.bin: $(MOS_SRCS) $(GEN)
	$(MADS) -d:CART_EF=1 -i:src/mos -i:$(BUILD)/gen -l:$(BUILD)/mos-ef.lst -o:$@ src/mos/cart.s >/dev/null || \
		($(MADS) -d:CART_EF=1 -i:src/mos -i:$(BUILD)/gen -o:$@ src/mos/cart.s | grep -i -B1 error; rm -f $@; false)

$(BUILD)/mos-tmb.bin: $(MOS_SRCS) $(GEN)
	$(MADS) -d:CART_TMB=1 -i:src/mos -i:$(BUILD)/gen -l:$(BUILD)/mos-tmb.lst -o:$@ src/mos/cart.s >/dev/null || \
		($(MADS) -d:CART_TMB=1 -i:src/mos -i:$(BUILD)/gen -o:$@ src/mos/cart.s | grep -i -B1 error; rm -f $@; false)

# --- Help texts: banks 3+ and the Markdown reference

$(BUILD)/help.bin: src/help/help.txt tools/genhelp.py src/mos/mos.s
	@$(MKDIR) $(BUILD)
	$(PYTHON) tools/genhelp.py --commands src/mos/mos.s src/help/help.txt $@ docs/HELP_REFERENCE.md

docs/HELP_REFERENCE.md: $(BUILD)/help.bin

# --- Cartridges

$(BUILD)/$(NAME)-ef.crt: $(BUILD)/mos-ef.bin $(BUILD)/basic.rom $(BUILD)/help.bin tools/mkcrt.py
	$(PYTHON) tools/mkcrt.py --type ef --name "U64 BBC BASIC" -o $@ $(BUILD)/mos-ef.bin:0 $(BUILD)/basic.rom $(BUILD)/mos-ef.bin:1 $(BUILD)/help.bin

$(BUILD)/$(NAME)-tmb.crt: $(BUILD)/mos-tmb.bin $(BUILD)/basic.rom $(BUILD)/help.bin tools/mkcrt.py
	$(PYTHON) tools/mkcrt.py --type tmb --name "U64 BBC BASIC" -o $@ $(BUILD)/mos-tmb.bin:0 $(BUILD)/basic.rom $(BUILD)/mos-tmb.bin:1 $(BUILD)/help.bin

# --- Ultimate settings, loaded with the cartridge when it is started from
# the Ultimate's file browser (firmware 3.15+: same name, same directory)

$(BUILD)/%.cfg: src/cfg/$(NAME).cfg
	@$(MKDIR) $(BUILD)
	cp $< $@

checkcfg:
	$(PYTHON) tools/checkcfg.py src/cfg/$(NAME).cfg $(ULTIP1) $(ULTIP2)

# --- The unpatched interpreter must still match Ivo's reference ROM

compare-core:
	@$(MKDIR) $(BUILD)/core
	cp -r $(BASICLIB)/. $(BUILD)/core/
	$(MAKE) -s -C $(BUILD)/core MADS=$(MADS) basic310hi.rom compare310hi

# --- Testing

vice: $(BUILD)/$(NAME)-ef.crt
	$(X64) -cartcrt $< &

e2e: $(CRTS) checkcfg
	$(PYTHON) tests/e2e/run_e2e.py

e2e-vice: $(CRTS)
	$(PYTHON) tests/e2e/run_e2e.py --vice-only

e2e-u64: $(CRTS) checkcfg
	$(PYTHON) tests/e2e/run_e2e.py --no-vice

# --- Deploy to the Ultimates' RAM disk (gone after a power cycle)

check-deploy:
	@curl -s --connect-timeout 3 ftp://$(ULTIP1)/ >/dev/null 2>&1 || \
		(echo "ERROR: Cannot reach the Ultimate at $(ULTIP1) -- check ULTIP1 in .env" && false)

deploy: check-deploy $(CRTS) $(CFGS)
	curl -s -T "{$(subst $(space),$(comma),$(CRTS) $(CFGS))}" ftp://$(ULTIP1)$(ULTPATH)
ifdef ULTIP2
	curl -s -T "{$(subst $(space),$(comma),$(CRTS) $(CFGS))}" ftp://$(ULTIP2)$(ULTPATH)
endif

clean:
	rm -rf $(BUILD)
