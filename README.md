# MOTDgd SourceMod Plugin

## Required extensions:
- Socket ( https://forums.alliedmods.net/showthread.php?t=67640 )

## Installation instructions:
- Click "Clone or download" and click on "Download ZIP"
- Extract the ZIP in the main directory of your server
- Set your MOTDgd ID in cfg/sourcemod/plugin.motdgd_adverts.cfg

## Rewards:

To set up rewards, you can use the command "sm_motdgd_add_reward". For example:

sm_motdgd_add_reward "sm_slay #{userid}"

For weighted probability mode, you can set the weight of the reward with the optional second parameter:

sm_motdgd_add_reward "sm_slay #{userid}" 10
