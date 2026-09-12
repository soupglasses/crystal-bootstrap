# Exercise startup, fiber scheduling, subprocess IO and shutdown as a program.
channel = Channel(Int32).new
spawn { channel.send(42) }
puts channel.receive
status = Process.run("printf", ["child\n"], output: STDOUT)
raise "child failed" unless status.success?
