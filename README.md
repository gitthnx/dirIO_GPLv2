# dirIO

    Linux cmdline script for directory monitoring, e.g. data io (MB/s)

![dirIO graphical output](https://github.com/gitthnx/dirIO_GPLv2/blob/main/tmp/Screenshot_dirIO_graphical.png)
    

### syntax and keys 

    ./dirIO.sh --help 
 

       Usage: ./dirIO__du.sh  /directory/to/monitor
                                             
              keys: on 'statx' errors == 'n'        
                    pause             == 'p'        
                    resume            == ' ' or 'r' 
                    quit              == 'q' or 'Q' 
                                             
              version 0.1                           
              June 15, 2024                         

### start
    ./dirIO.sh /path/to/directory/for/monitoring/data_io


### chatGPT assisted code creation, initial prompt command:
    Create a code example for data input output monitoring and data rate output within a bash shell command line. Create this script as bash shell script. Create this script for filesystem data input and data output and data rates from or to this directory, that is declared with script variables on startup. Add request for keyboard input for stopping that script on pressing q or Q. Add keyboard input scan for pausing output with pressing p and resuming with space key.
