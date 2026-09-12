# Macro shell commands and regex matching communicate through caller-local slots.
output = `printf child`
raise "wrong output" unless output == "child"
puts $?.success?
"abc123".match(/([0-9]+)/)
puts $~[1]
