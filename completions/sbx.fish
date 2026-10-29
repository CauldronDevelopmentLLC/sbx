# Helper function to list existing sandboxes
function __fish_sbx_sandboxes
    set -q XDG_CONFIG_HOME || set XDG_CONFIG_HOME $HOME/.config
    path filter -d $XDG_CONFIG_HOME/sbx/containers/* | path basename
end

# Helper function to list templates, <name>.yml or <name>/config.yml, the
# user's and those installed with sbx
function __fish_sbx_templates
    set -q XDG_CONFIG_HOME || set XDG_CONFIG_HOME $HOME/.config
    set -l lib (path resolve (command -s sbx) | path dirname)
    test -d $lib/../lib/sbx && set lib $lib/../lib/sbx # Else a checkout
    set -l files $XDG_CONFIG_HOME/sbx/templates/{*.yml,*/config.yml} \
        $lib/templates/{*.yml,*/config.yml} # No error if none
    string replace -r '(/config)?\.yml$' '' $files | path basename | sort -u
end

# Helper function to list the rules available
function __fish_sbx_rules
    sbx list-rules 2>/dev/null | string replace -r ' .*' ''
end

# Common options
complete -x -c sbx -s h -l help -d 'Display help and exit'
complete -x -c sbx -s v -l verbose -d 'Enable verbose logging' -n __fish_is_first_arg

# Subcommands
complete -x -c sbx -n __fish_use_subcommand -a create -d 'Create a new sandbox'
complete -x -c sbx -n __fish_use_subcommand -a delete -d 'Delete an existing sandbox'
complete -x -c sbx -n __fish_use_subcommand -a edit -d 'Edit sandbox config'
complete -x -c sbx -n __fish_use_subcommand -a list -d 'List existing sandboxes'
complete -x -c sbx -n __fish_use_subcommand -a list-rules -d 'List available rules'
complete -x -c sbx -n __fish_use_subcommand -a ps -d 'List running sandboxes'
complete -x -c sbx -n __fish_use_subcommand -a rename -d 'Rename an existing sandbox'
complete -x -c sbx -n __fish_use_subcommand -a run -d 'Run an existing sandbox'
complete -x -c sbx -n __fish_use_subcommand -a show -d 'Print sandbox config and exit'
complete -x -c sbx -n __fish_use_subcommand -a update -d 'Update a sandbox, e.g. its program'
complete -x -c sbx -n __fish_use_subcommand -a enter -d 'Enter a running sandbox'
complete -x -c sbx -n __fish_use_subcommand -a template -d 'Create a template from an existing sandbox'

# Options for 'create' subcommand
complete -x -c sbx -n '__fish_seen_subcommand_from create' -s r -l rule -d 'Rule or rules to apply, in addition to the template\'s' -a '(__fish_sbx_rules)'
complete -c sbx -n '__fish_seen_subcommand_from create' -s t -l template -d 'Template to import, or a path' -a '(__fish_sbx_templates)'

# Options for 'delete' subcommand
complete -f -c sbx -n '__fish_seen_subcommand_from delete' -s f -l force -d 'Delete without asking'

# Options for 'list-rules' subcommand
complete -c sbx -n '__fish_seen_subcommand_from list-rules' -s c -l config -d 'Template or path to list the rules of' -a '(__fish_sbx_templates)'

# Options for 'run' subcommand
complete -f -c sbx -n '__fish_seen_subcommand_from run' -s C -l command -d 'Override the sandbox command'

# Options for 'template' subcommand
complete -f -c sbx -n '__fish_seen_subcommand_from template' -s f -l force -d 'Overwrite existing template'

# Subcommands that take a sandbox name
for cmd in delete edit enter rename run show template update
    complete -x -c sbx -n "__fish_seen_subcommand_from $cmd" -a "(__fish_sbx_sandboxes)" -d Sandbox
end
