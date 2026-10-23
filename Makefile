# U64 BBC BASIC -- BBC BASIC 3.10 for the Ultimate 64 / C64 Ultimate
#
# make            build both cartridges in build/
# make compare-core   check the unpatched BASIC 3.10 against Ivo's reference
# make e2e        end-to-end tests through c64bridge (tests/e2e/README.md)
# make vice       run the EasyFlash cartridge in VICE
# make deploy     upload the cartridges to the Ultimates in .env
# make vscode     build the VS Code extension (build/u64-bbcbasic.vsix)
# make vscode-test  extension tests (offline, device, inside VS Code)
# make docs       the user manual as PDF (build/U64_BBC_BASIC_MANUAL.pdf)
# make release    the release ZIP and .vsix (build/u64-bbcbasic-<version>.*)

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
GEN       = $(BUILD)/gen/tables.s $(BUILD)/gen/ul_r1.s $(BUILD)/gen/ul_r2.s \
            $(BUILD)/gen/ul_r3.s $(BUILD)/gen/ul_r4.s $(BUILD)/gen/sound_tables.s \
            $(BUILD)/gen/sound_inst.s $(BUILD)/gen/list_tokens.s \
            $(BUILD)/gen/upic_r64.s $(BUILD)/gen/upic_r48.s \
            $(BUILD)/gen/font4x6.s $(BUILD)/gen/math_tables.s \
            $(BUILD)/gen/cfg_text.s

ULTIP1   ?= <set_ULTIP1_in_.env>
ULTPATH   = /Temp/

CRTS      = $(BUILD)/$(NAME)-tmb.crt $(BUILD)/$(NAME)-ef.crt
CFGS      = $(CRTS:.crt=.cfg)

.PHONY: all clean compare-core e2e e2e-vice e2e-u64 vice deploy check-deploy checkcfg vscode vscode-test manual docs release

# the version: the extension's package.json (the same as the banner, *STATUS
# and CHANGELOG.md)
VERSION  := $(shell sed -n 's/^  "version": "\(.*\)",/\1/p' vscode/package.json)

all: $(CRTS) $(CFGS) $(BUILD)/manual.stamp

# --- BBC BASIC 3.10 for $8000, from Ivo van Poorten's source + our target

$(BASICDIR)/basic.s: $(BASICSRC) src/basic/u64-target.patch
	@$(MKDIR) $(BASICDIR)
	cp $(BASICSRC) $(BASICDIR)/
	patch -s -d $(BASICDIR) -p1 < src/basic/u64-target.patch

$(BUILD)/basic.rom: $(BASICDIR)/basic.s
	$(MADS) -d:BUILD_U64_BASIC310=1 -l:$(BUILD)/basic.lst -o:$@ $< >/dev/null

# --- MOS bank 0, one per cartridge type

$(BUILD)/gen/sound_tables.s $(BUILD)/gen/sound_inst.s: tools/gensound.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< -o $(BUILD)/gen/sound_tables.s --instruments $(BUILD)/gen/sound_inst.s

$(BUILD)/gen/list_tokens.s: tools/genlist.py tools/bbctok.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< -o $@

$(BUILD)/gen/cfg_text.s: tools/gencfgtext.py src/cfg/$(NAME).cfg
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< src/cfg/$(NAME).cfg -o $@

$(BUILD)/gen/math_tables.s: tools/genmath.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< -o $@

$(BUILD)/gen/tables.s: tools/gentables.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< $@

# Upic Lite line renderers (tools/upiclite_gen.py; delays calibrated on
# the U64-II: pixel 0 on dot 32, docs/DESIGN_GRAPHICS.md section 10.8)
$(BUILD)/gen/ul_r1.s: tools/upiclite_gen.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< --bpp 1 --cols '$$5800' --tables '$$E900' --delay 172 --label ul1_line -o $@
$(BUILD)/gen/ul_r2.s: tools/upiclite_gen.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< --bpp 2 --cols '$$3000' --tables '$$E900' --delay 140 --label ul2_line -o $@
$(BUILD)/gen/ul_r3.s: tools/upiclite_gen.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< --bpp 2 --width 160 --dots 2 --cols '$$5800' --tables '$$E900' --delay 172 --label ul3_line -o $@
$(BUILD)/gen/ul_r4.s: tools/upiclite_gen.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< --bpp 4 --width 160 --dots 2 --cols '$$3000' --tables '$$E900' --delay 172 --label ul4_line -o $@

# MODE 1 on the VIC-II: the 4x6 font (X11 misc-fixed, public domain)
$(BUILD)/gen/font4x6.s: tools/genfont4x6.py src/fonts/4x6.bdf
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< src/fonts/4x6.bdf -o $@

# Upic full line renderers (tools/upic_gen.py, after ultimate-uci-oscar64's
# Upic module; columns at $1000, nybble table at $0E00, run at $0400)
$(BUILD)/gen/upic_r64.s: tools/upic_gen.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< --path 64 --nyb '$$0E00' --label upr64 -o $@
$(BUILD)/gen/upic_r48.s: tools/upic_gen.py
	@$(MKDIR) $(dir $@)
	$(PYTHON) $< --path 48 --nyb '$$0E00' --label upr48 -o $@

# banks 0 and 2 in one assembly (src/mos/cart.s): 32K, bank 0 then bank 2
$(BUILD)/mos-ef.bin: $(MOS_SRCS) $(GEN)
	$(MADS) -d:CART_EF=1 -i:src/mos -i:$(BUILD)/gen -l:$(BUILD)/mos-ef.lst -t:$(BUILD)/mos-ef.lab -o:$@ src/mos/cart.s >/dev/null || \
		($(MADS) -d:CART_EF=1 -i:src/mos -i:$(BUILD)/gen -o:$@ src/mos/cart.s | grep -i -B1 error; rm -f $@; false)

$(BUILD)/mos-tmb.bin: $(MOS_SRCS) $(GEN)
	$(MADS) -d:CART_TMB=1 -i:src/mos -i:$(BUILD)/gen -l:$(BUILD)/mos-tmb.lst -t:$(BUILD)/mos-tmb.lab -o:$@ src/mos/cart.s >/dev/null || \
		($(MADS) -d:CART_TMB=1 -i:src/mos -i:$(BUILD)/gen -o:$@ src/mos/cart.s | grep -i -B1 error; rm -f $@; false)

# --- Help texts: banks 3+ and the Markdown reference

$(BUILD)/help.bin: src/help/help.txt tools/genhelp.py src/mos/mos.s Makefile
	@$(MKDIR) $(BUILD)
	$(PYTHON) tools/genhelp.py --first 11 --commands src/mos/mos.s src/help/help.txt $@ docs/HELP_REFERENCE.md

docs/HELP_REFERENCE.md: $(BUILD)/help.bin

# The user manual: docs/manual/src chapters with the *HELP texts filled in
MANUAL_SRC := $(wildcard docs/manual/src/*.md)
$(BUILD)/manual.stamp: $(MANUAL_SRC) src/help/help.txt tools/genmanual.py
	$(PYTHON) tools/genmanual.py src/help/help.txt docs/manual/src docs/manual
	@mkdir -p $(BUILD) && touch $@
manual: $(BUILD)/manual.stamp

# The manual as one PDF (pandoc, xelatex; DejaVu for the arrows and £)
MANUAL_MD := $(sort $(wildcard docs/manual/[0-9]*.md))
docs: $(BUILD)/U64_BBC_BASIC_MANUAL.pdf

$(BUILD)/U64_BBC_BASIC_MANUAL.pdf: $(BUILD)/manual.stamp $(MANUAL_MD)
	@which pandoc >/dev/null 2>&1 || \
		(echo "pandoc not found -- install with: sudo apt install pandoc texlive-xetex" && false)
	pandoc --pdf-engine=xelatex --toc -V mainfont="DejaVu Serif" -V monofont="DejaVu Sans Mono" \
		-V geometry:a4paper,margin=2.2cm -V colorlinks=true \
		-M title="U64 BBC BASIC $(VERSION)" -M subtitle="User manual" -o $@ $(MANUAL_MD)

# --- Cartridges

$(BUILD)/$(NAME)-ef.crt: $(BUILD)/mos-ef.bin $(BUILD)/basic.rom $(BUILD)/help.bin tools/mkcrt.py
	$(PYTHON) tools/mkcrt.py --type ef --name "U64 BBC BASIC" -o $@ $(BUILD)/mos-ef.bin:0 $(BUILD)/basic.rom $(BUILD)/mos-ef.bin:1 $(BUILD)/mos-ef.bin:2 $(BUILD)/mos-ef.bin:3 $(BUILD)/mos-ef.bin:4 $(BUILD)/mos-ef.bin:5 $(BUILD)/mos-ef.bin:6 $(BUILD)/mos-ef.bin:7 $(BUILD)/mos-ef.bin:8 $(BUILD)/mos-ef.bin:9 $(BUILD)/help.bin

$(BUILD)/$(NAME)-tmb.crt: $(BUILD)/mos-tmb.bin $(BUILD)/basic.rom $(BUILD)/help.bin tools/mkcrt.py
	$(PYTHON) tools/mkcrt.py --type tmb --name "U64 BBC BASIC" -o $@ $(BUILD)/mos-tmb.bin:0 $(BUILD)/basic.rom $(BUILD)/mos-tmb.bin:1 $(BUILD)/mos-tmb.bin:2 $(BUILD)/mos-tmb.bin:3 $(BUILD)/mos-tmb.bin:4 $(BUILD)/mos-tmb.bin:5 $(BUILD)/mos-tmb.bin:6 $(BUILD)/mos-tmb.bin:7 $(BUILD)/mos-tmb.bin:8 $(BUILD)/mos-tmb.bin:9 $(BUILD)/help.bin

# --- Ultimate settings, loaded with the cartridge when it is started from
# the Ultimate's file browser (firmware 3.15+: same name, same directory)

$(BUILD)/%.cfg: src/cfg/$(NAME).cfg
	@$(MKDIR) $(BUILD)
	cp $< $@

checkcfg:
	$(PYTHON) tools/checkcfg.py src/cfg/$(NAME).cfg $(ULTIP1) $(ULTIP2)

# the cartridge's settings on the devices (after lending a U64 out)
applycfg:
	$(PYTHON) tools/applycfg.py src/cfg/$(NAME).cfg $(ULTIP1) $(ULTIP2)

# --- The unpatched interpreter must still match Ivo's reference ROM

compare-core:
	@$(MKDIR) $(BUILD)/core
	cp -r $(BASICLIB)/. $(BUILD)/core/
	$(MAKE) -s -C $(BUILD)/core MADS=$(MADS) basic310hi.rom compare310hi

# --- Testing

vice: $(BUILD)/$(NAME)-ef.crt
	$(X64) -cartcrt $< &

# GROUP=graphics (or several, quoted) runs only those groups
E2E_GROUPS = --split $(if $(GROUP),--group $(GROUP))

e2e: $(CRTS) checkcfg
	$(PYTHON) tests/e2e/run_e2e.py $(E2E_GROUPS)

e2e-vice: $(CRTS)
	$(PYTHON) tests/e2e/run_e2e.py --vice-only $(E2E_GROUPS)

e2e-u64: $(CRTS) checkcfg
	$(PYTHON) tests/e2e/run_e2e.py --no-vice $(E2E_GROUPS)

# --- Deploy to the Ultimates: /<drive>/idi8b/u64bbcbasic/ (cartridges,
# .cfg) and its demos/ (tokenised programs and their files); the drive per
# machine in .env (ULTDRV1, ULTDRV2: SD, USB0, ...; default USB0). The
# second Ultimate only if it answers.

ULTDRV1 ?= USB0
ULTDRV2 ?= USB0

check-deploy:
	@curl -s --connect-timeout 3 ftp://$(ULTIP1)/ >/dev/null 2>&1 || \
		(echo "ERROR: Cannot reach the Ultimate at $(ULTIP1) -- check ULTIP1 in .env" && false)

deploy: check-deploy $(CRTS) $(CFGS)
	$(PYTHON) tools/deploy.py --host $(ULTIP1) --drive $(ULTDRV1) $(CRTS) $(CFGS)
ifdef ULTIP2
	@if curl -s --connect-timeout 3 ftp://$(ULTIP2)/ >/dev/null 2>&1; then \
		$(PYTHON) tools/deploy.py --host $(ULTIP2) --drive $(ULTDRV2) $(CRTS) $(CFGS); \
	else echo "Skipped $(ULTIP2): not reachable"; fi
endif

# --- VS Code extension (vscode/): build/u64-bbcbasic.vsix

vscode:
	cd vscode && npm install --no-fund --no-audit && npm run package

# --- Release: the ZIP (tools/mkrelease.py) and the .vsix, both versioned

release: all docs vscode
	$(PYTHON) tools/mkrelease.py $(VERSION)
	cp $(BUILD)/u64-bbcbasic.vsix $(BUILD)/u64-bbcbasic-$(VERSION).vsix

vscode-test:
	cd vscode && npm test && U64_HOST=$(ULTIP1) npm run test:device && U64_HOST=$(ULTIP1) npm run test:vscode

clean:
	rm -rf $(BUILD)
