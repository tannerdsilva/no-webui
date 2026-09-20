# no-webui — Hermes agent skill installer
#
# Installs this repo's agent skill (SKILL.md, plus any references/ tree) into
# the active Hermes profile's skill library so the Hermes agent can load the
# `no-webui` skill. The skill's metadata.hermes.related_skills let the agent
# find the companion `webui-design-system` skill if that is installed too.
#
#   make install-skill                  # install into the current profile
#   make install-skill PROFILE=webui    # install into a named profile
#   make install-skill HERMES_ROOT=~/x  # override the hermes root
#   make uninstall-skill                # remove the installed skill
#   make skill-info                     # print the install target
#
# The install target is derived from the repo SKILL.md frontmatter (`name`
# + the category the related web-ui skills live under). These are overridable:
#   SKILL_NAME, SKILL_CATEGORY, HERMES_PROFILE, HERMES_ROOT

HERMES_ROOT      ?= $(HOME)/.hermes
HERMES_PROFILE   ?= browser-dev
SKILL_NAME       := no-webui
SKILL_CATEGORY   := creative

SKILL_DIR := $(HERMES_ROOT)/profiles/$(HERMES_PROFILE)/skills/$(SKILL_CATEGORY)/$(SKILL_NAME)

.PHONY: install-skill uninstall-skill skill-info

# Install the repo skill (SKILL.md + optional references/) into the profile.
install-skill:
	@mkdir -p "$(SKILL_DIR)"
	@cp SKILL.md "$(SKILL_DIR)/SKILL.md"
	@if [ -d references ]; then cp -R references "$(SKILL_DIR)/"; fi
	@echo "  Installed '$(SKILL_NAME)' skill → $(SKILL_DIR)"
	@echo "  (related: $(SKILL_CATEGORY)/webui-design-system)"

# Remove the installed skill.
uninstall-skill:
	@rm -rf "$(SKILL_DIR)"
	@echo "  Removed '$(SKILL_NAME)' skill at $(SKILL_DIR)"

# Print where the skill would be installed.
skill-info:
	@echo "  skill:     $(SKILL_NAME)"
	@echo "  category:  $(SKILL_CATEGORY)"
	@echo "  profile:   $(HERMES_PROFILE)"
	@echo "  target:    $(SKILL_DIR)"
