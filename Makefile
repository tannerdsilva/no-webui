# no-webui — Hermes agent skill installer
#
# Installs this repo's agent skill (SKILL.md, plus any references/ tree) into
# the active Hermes profile's skill library so the Hermes agent can load the
# `no-webui` skill. The skill's metadata.hermes.related_skills let the agent
# find the companion `webui-design-system` skill if that is installed too.
#
#   make install-skill                 # NON-INTERACTIVE (default): validate + install
#   make install-skill-interactive     # INTERACTIVE: prompt for root/profile/category
#   make uninstall-skill               # remove the installed skill
#   make skill-info                    # show defaults / target
#
# Overrides: PROFILE=<name>  HERMES_ROOT=<path>  SKILL_NAME=<name>
#            SKILL_CATEGORY=<cat>  FORCE=1 (overwrite an existing install)
#
# Non-interactive mode fails fast with guidance on misuse. Interactive mode
# prompts and confirms before writing.

HERMES_ROOT      ?= $(HOME)/.hermes
PROFILE   ?= browser-dev
SKILL_NAME       := no-webui
SKILL_CATEGORY   := creative

.PHONY: install-skill install-skill-interactive uninstall-skill skill-info

# ── Non-interactive install (default) ──────────────────────────────────
# Validates inputs; exits 1 with a fix on misconfiguration.
install-skill:
	@set -u; \
	name="$(SKILL_NAME)"; root="$(HERMES_ROOT)"; profile="$(PROFILE)"; cat_="$(SKILL_CATEGORY)"; force="$(FORCE)"; \
	dir="$$root/profiles/$$profile/skills/$$cat_/$$name"; \
	if [ ! -f SKILL.md ]; then \
		echo "error: SKILL.md not found." >&2; \
		echo "  This Makefile must be run from the no-webui repo root (where SKILL.md lives)." >&2; \
		echo "  fix: cd ~/workspace/no-webui && make install-skill" >&2; \
		exit 1; \
	fi; \
	if [ -z "$$profile" ]; then \
		echo "error: no Hermes profile given (PROFILE is empty)." >&2; \
		echo "  fix: make install-skill PROFILE=browser-dev" >&2; \
		exit 1; \
	fi; \
	if [ ! -d "$$root" ]; then \
		echo "error: Hermes root not found: $$root" >&2; \
		echo "  fix: point HERMES_ROOT at your Hermes config dir, e.g." >&2; \
		echo "       make install-skill HERMES_ROOT=$$HOME/.hermes" >&2; \
		exit 1; \
	fi; \
	if [ -d "$$dir" ] && [ -z "$$force" ]; then \
		echo "error: '$$name' is already installed at:" >&2; \
		echo "  $$dir" >&2; \
		echo "  fix: re-run with FORCE=1 to overwrite, or 'make uninstall-skill' first." >&2; \
		exit 1; \
	fi; \
	mkdir -p "$$dir"; \
	cp SKILL.md "$$dir/SKILL.md"; \
	if [ -d references ]; then cp -R references "$$dir/"; fi; \
	echo "  installed '$$name' skill → $$dir"; \
	echo "  (related: $$cat_/webui-design-system)"; \
	echo "  note: skills load on a fresh agent session."

# ── Interactive install ────────────────────────────────────────────────
# Prompts for root/profile/category (defaults in brackets), confirms, then
# installs. Also validates SKILL.md + the hermes root.
install-skill-interactive:
	@set -u; \
	root="$(HERMES_ROOT)"; profile="$(PROFILE)"; cat_="$(SKILL_CATEGORY)"; name="$(SKILL_NAME)"; \
	echo "no-webui skill installer (interactive)"; \
	echo "  defaults shown in brackets; press Enter to accept."; \
	if [ ! -f SKILL.md ]; then echo "error: SKILL.md not found (run from the repo root)." >&2; exit 1; fi; \
	printf "  Hermes root [%s]: " "$$root"; read r; [ -n "$$r" ] && root="$$r"; \
	printf "  Hermes profile [%s]: " "$$profile"; read r; [ -n "$$r" ] && profile="$$r"; \
	printf "  Skill category [%s]: " "$$cat_"; read r; [ -n "$$r" ] && cat_="$$r"; \
	if [ -z "$$profile" ]; then echo "error: profile cannot be empty." >&2; exit 1; fi; \
	if [ ! -d "$$root" ]; then echo "error: Hermes root not found: $$root" >&2; exit 1; fi; \
	dir="$$root/profiles/$$profile/skills/$$cat_/$$name"; \
	echo "  will install to: $$dir"; \
	if [ -d "$$dir" ]; then printf "  '$$name' already installed — overwrite? [y/N]: "; read r; \
		[ "$$r" = "y" ] || [ "$$r" = "Y" ] || { echo "  aborted."; exit 1; }; fi; \
	printf "  Continue? [y/N]: "; read r; \
	[ "$$r" = "y" ] || [ "$$r" = "Y" ] || { echo "  aborted."; exit 1; }; \
	mkdir -p "$$dir"; \
	cp SKILL.md "$$dir/SKILL.md"; \
	if [ -d references ]; then cp -R references "$$dir/"; fi; \
	echo "  installed '$$name' skill → $$dir"; \
	echo "  note: skills load on a fresh agent session."

# ── Uninstall ──────────────────────────────────────────────────────────
uninstall-skill:
	@set -u; \
	name="$(SKILL_NAME)"; root="$(HERMES_ROOT)"; profile="$(PROFILE)"; cat_="$(SKILL_CATEGORY)"; \
	dir="$$root/profiles/$$profile/skills/$$cat_/$$name"; \
	if [ ! -d "$$dir" ]; then \
		echo "error: '$$name' is not installed (nothing to remove)." >&2; \
		echo "  target checked: $$dir" >&2; \
		exit 1; \
	fi; \
	rm -rf "$$dir"; \
	echo "  removed '$$name' skill at $$dir"

# ── Info ───────────────────────────────────────────────────────────────
skill-info:
	@echo "  skill:     $(SKILL_NAME)"
	@echo "  category:  $(SKILL_CATEGORY)"
	@echo "  profile:   $(PROFILE)"
	@echo "  target:    $(HERMES_ROOT)/profiles/$(PROFILE)/skills/$(SKILL_CATEGORY)/$(SKILL_NAME)"
	@echo ""; \
	echo "  default: make install-skill (non-interactive)"
	echo "  interactive: make install-skill-interactive"
