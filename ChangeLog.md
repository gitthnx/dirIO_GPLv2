............

??/2025
v0.1.?.?    summary file/'output option/section' for biggest files/directories ( | tail -n 10 ) causing IO during monitoring (WIP)
            alternative approach ( 1)_find/du 2)_inotifywait ~~3)_bpftrace~~ ) for getting IO events (WIP)

............

0?/2025
v0.1.7.x    improved start-up for analyzing filesystems with high amount of files within single folders (WIP)

............

04/2025
v0.1.6.1    intermediate test version (slightly improved for huge filesystems and high amount of files), testing different approaches
            reorganized output sections for varying terminal sizes (WIP)

03/2025
v0.1.6.0    improved start-up for analyzing filesystems larger than 32GB of tree size and extendended path levels
            (requiring adjusted version of 'inotify-tools' on v0.1.6.0.x versions for coherent functionality, because of logging file sizes is required)


............

03/2025
v0.1.5.x    initial advanced version including graphical output and implemention of 'inotifywait' (origin:  for logging modified (signalled by 
            events CREATE, MODIFY, MOVE_TO, MOVE_FROM, DELETE) files and directories


............

03/2025
v0.1.2      versions including graphical visualization of data IO for the analyzed directory (and possible sub-directories)
v0.1.1


............

06/2024
v0.1        initial published version


............
