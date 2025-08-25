fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'VeraRP'
description 'Paid metro rides with door-close fare + /trains UI'
version '1.1.0'

shared_scripts {
  '@qb-core/shared/locale.lua',
  'config.lua'
}

client_scripts {
  'client.lua'
}

server_scripts {
  'server.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html'
}

dependencies {
  'qb-core'
}
