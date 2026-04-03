fx_version 'cerulean'
game 'rdr3'
lua54 'yes'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'fr0st'
description 'Standalone herb gathering resource for RSG RedM'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/helpers.lua',
    'shared/zones.lua',
}

client_scripts {
    'client/main.lua',
    'client/admin.lua',
}

server_scripts {
    'server/admin.lua',
    'server/main.lua',
}

files {
    'data/items.lua',
    'data/zones.json',
}

dependencies {
    'ox_lib',
    'rsg-core',
    'rsg-inventory',
}
