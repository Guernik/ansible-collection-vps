function gitc --description "Switch to an existing git branch"
    if test (count $argv) -eq 0
        echo "Usage: gitc <branch>"
        return 1
    end

    git checkout $argv[1]
end
