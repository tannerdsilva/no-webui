# no-webui — Hermes agent skill installer
#
# Installs this repo's agent skills (SKILL.md, plus any references/ tree) into
# the active Hermes profile's skill library so the Hermes agent can load them:
#
#   - `no-webui`            — from ./SKILL.md
#   - `webui-design-system` — from skills/webui-design-system/
#
# The two skills link each other via metadata.hermes.related_skills.
#
#   make install-skill                # NON-INTERACTIVE (default): validate + install both
#   make install-skill INTERACTIVE=1  # INTERACTIVE: prompt for root/profile/category
#   make uninstall-skill              # remove both installed skills
#   make skill-info                   # show defaults / targets
#
# Overrides: PROFILE=<name>  HERMES_ROOT=<path>  FORCE=1 (overwrite existing
#            installs)  INTERACTIVE=1 (prompt + confirm)
#
# Non-interactive mode fails fast with guidance on misuse. Interactive mode
# prompts and confirms before writing.

HERMES_ROOT     ?= $(HOME)/.hermes
PROFILE         ?= browser-dev
SKILL_CATEGORY  := creative

# name -> source dir (where that skill's SKILL.md + references/ live).
NO_WEBUI_SRC := .
WDS_SRC      := skills/webui-design-system

.PHONY: install-skill uninstall-skill skill-info

install-skill:
	@set -eu; \
	root="$(HERMES_ROOT)"; profile="$(PROFILE)"; cat_="$(SKILL_CATEGORY)"; force="$(FORCE)"; interactive="$(INTERACTIVE)"; \
	if [ "$$interactive" = "1" ]; then \
		echo "no-webui skill installer (interactive)"; \
		echo "  defaults shown in brackets; press Enter to accept."; \
		printf "  Hermes root [%s]: " "$$root"; read r; [ -n "$$r" ] && root="$$r"; \
		printf "  Hermes profile [%s]: " "$$profile"; read r; [ -n "$$r" ] && profile="$$r"; \
		printf "  Skill category [%s]: " "$$cat_"; read r; [ -n "$$r" ] && cat_="$$r"; \
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
	for name in no-webui webui-design-system; do \
		case "$$name" in \
		  no-webui) src="$(NO_WEBUI_SRC)" ;; \
		  webui-design-system) src="$(WDS_SRC)" ;; \
		esac; \
		if [ ! -f "$$src/SKILL.md" ]; then \
			echo "error: $$src/SKILL.md not found for '$$name'." >&2; \
			echo "  this Makefile must be run from the repo root." >&2; \
			exit 1; \
		fi; \
		dir="$$root/profiles/$$profile/skills/$$cat_/$$name"; \
		if [ -d "$$dir" ]; then \
			if [ "$$interactive" = "1" ]; then \
				printf "  '$$name' already installed — overwrite? [y/N]: "; read r; \
				[ "$$r" = "y" ] || [ "$$r" = "Y" ] || { echo "  aborted."; exit 1; }; \
			elif [ -z "$$force" ]; then \
				echo "error: '$$name' is already installed at:" >&2; \
				echo "  $$dir" >&2; \
				echo "  fix: re-run with FORCE=1 to overwrite, or 'make uninstall-skill' first." >&2; \
				exit 1; \
			fi; \
		fi; \
		if [ "$$interactive" = "1" ]; then \
			printf "  install '$$name' to $$dir? [y/N]: "; read r; \
			[ "$$r" = "y" ] || [ "$$r" = "Y" ] || { echo "  aborted."; exit 1; }; \
		fi; \
		mkdir -p "$$dir"; \
		cp "$$src/SKILL.md" "$$dir/SKILL.md"; \
		if [ -d "$$src/references" ]; then cp -R "$$src/references" "$$dir/"; fi; \
		echo "  installed '$$name' skill → $$dir"; \
	done; \
	echo "  note: skills load on a fresh agent session."

# ── Uninstall ──────────────────────────────────────────────────────────
uninstall-skill:
	@set -eu; \
	root="$(HERMES_ROOT)"; profile="$(PROFILE)"; cat_="$(SKILL_CATEGORY)"; \
	for name in no-webui webui-design-system; do \
		dir="$$root/profiles/$$profile/skills/$$cat_/$$name"; \
		if [ -d "$$dir" ]; then \
			rm -rf "$$dir"; \
			echo "  removed '$$name' skill at $$dir"; \
		else \
			echo "  note: '$$name' not installed ($$dir)"; \
		fi; \
	done

# ── Info ───────────────────────────────────────────────────────────────
skill-info:
	@echo "  skills:     no-webui (./SKILL.md), webui-design-system (skills/webui-design-system/)"
	@echo "  category:   $(SKILL_CATEGORY)"
	@echo "  profile:    $(PROFILE)"
	@echo "  target:     $(HERMES_ROOT)/profiles/$(PROFILE)/skills/$(SKILL_CATEGORY)/{no-webui,webui-design-system}"
	@echo ""
	@echo "  default:       make install-skill (non-interactive)"
	@echo "  interactive:   make install-skill INTERACTIVE=1"
