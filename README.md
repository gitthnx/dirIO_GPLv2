
# dirIO

    Linux cmdline script for directory monitoring, e.g. data io (MB/s)
    (limited to about 32GB directory path size, including sub-directories,
     for useful functional monitoring)

![dirIO graphical output](https://github.com/gitthnx/dirIO_GPLv2/blob/main/tmp/dirIO_v0.1.5.2_2025-03-30.png)
<!-- p align="left"> https://github.com/gitthnx/dirIO_GPLv2/blob/main/tmp/Screenshot_dirIO_light_graphical.png -->   
<br>


### syntax and keys 

    ./dirIO.sh --help 
<br> 

       Usage: ./dirIO.sh  /directory/to/monitor
                                             
       keys: search tree level       == 'N'up 'n'dn        
             output mode             == 'm'        
             pause                   == 'p'        
             resume                  == ' ' or 'r' 
             clear screen            == 'c' or 'C' 
             help                    == 'h' or 'H' or '?'  
             quit                    == 'q' or 'Q' 
                                             
       version 0.1.5.2                          
       March 29, 2025                        
                    
<br>


### start
      # prepare for Your preferred inotifywait binary being available:
      sudo apt-get install inotify-tools
      whereis inotifywait
      cp /usr/bin/inotifywait /dev/shm/
      (copying .libs folder not necessary)

      # or from cloned git repository 'inotify-tools'
      # git clone https://github.com/gitthnx/inotify-tools 
      # built './autogen.sh; mkdir build; cd build; ../configure; make -j12;' 
      # inside build folder: 'build/src/.libs'
      cp <path to inotify-tools repository>/build/src/inotifywait /dev/shm
      cp <path to inotify-tools repository>/build/src/.libs -R /dev/shm 

      chmod +x ./dirIO.sh
    
     ./dirIO.sh /path/to/directory/for/monitoring/data_io
<br>


### notes & issues
*1) 'graphical' visualization only partially implemented within scripts for testing functionality options in \<tmp\> directory*
    
<!-- pre><p align="left"><a href="https://github.com/gitthnx/dirIO_GPLv2"><img width="500" src="https://github.com/gitthnx/dirIO_GPLv2/blob/main/tmp/Screenshot_dirIO_light_graphical.png" /></a></p></pre -->

<pre><!-- --><img src="https://github.com/gitthnx/dirIO_GPLv2/blob/main/tmp/Screenshot_dirIO_light_graphical.png" width="500" style="margin:30px" style="padding:30px;" ></pre>

<!-- *2) experimental implementation into C source code in \<tmp_C\> directory  
    partly done by LLM_chat automated source code conversion from shell to C source code* -->

<!-- div id="div1" name="div1" style="position:relative; top:10; left:50;" position="absolute" top="0" left="50" ><img width="500" src="https://github.com/gitthnx/dirIO_GPLv2/blob/main/tmp/Screenshot_dirIO_light_graphical.png"></div -->

<!-- *prev2) <noscript>from \<noscript\> tag: gitREADME.md does not support JavaScript</noscript>* -->

<!-- prev3) update local repository with changes:
        git config core.fileMode true
        git pull origin main
        alternative procedure:
        git stash push --include-untracked
        git stash drop
        or:
        git reset --hard
        git pull
-->
<br>

  
### chatGPT assisted code creation, initial prompt command:
    Create a code example for data input output monitoring and data rate output within a bash shell command line. 
    Create this script as bash shell script. 
    Create this script for filesystem data input and data output and data rates from or to this directory, that is declared with script variables on startup. 
    Add request for keyboard input for stopping that script on pressing q or Q. 
    Add keyboard input scan for pausing output with pressing p and resuming with space key.
<br><br>

### credits
  inotify   
  [inotify-tools](https://github.com/inotify-tools/inotify-tools)  
  [inotify-info](https://github.com/mikesart/inotify-info)

