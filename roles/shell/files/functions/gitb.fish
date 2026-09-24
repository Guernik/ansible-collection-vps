function gitb --description "Create and switch to a new git branch"
    if test (count $argv) -eq 0
        echo "Usage: gitb <branch>"
        return 1
    end

    git checkout -b $argv[1]
end
