#!/bin/bash
if [[ $(id -u) -ne 0 ]] ; then
    echo "Please run with sudo"
    exit 1
fi

function multiselect {
    ESC=$( printf "\033")
    cursor_blink_on()   { printf "$ESC[?25h"; }
    cursor_blink_off()  { printf "$ESC[?25l"; }
    cursor_to()         { printf "$ESC[$1;${2:-1}H"; }
    print_inactive()    { printf "$2   $1 "; }
    print_active()      { printf "$2  $ESC[7m $1 $ESC[27m"; }
    get_cursor_row()    { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }

    local return_value=$1
    local -n options=$2
    local -n defaults=$3

    local selected=()
    for ((i=0; i<${#options[@]}; i++)); do
        if [[ ${defaults[i]} = "true" ]]; then
            selected+=("true")
        else
            selected+=("false")
        fi
        printf "\n"
    done

    # determine current screen position for overwriting the options
    local lastrow=`get_cursor_row`
    local startrow=$(($lastrow - ${#options[@]}))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    key_input() {
        local key
        IFS= read -rsn1 key 2>/dev/null >&2
        if [[ $key = ""      ]]; then echo enter; fi;
        if [[ $key = $'\x20' ]]; then echo space; fi;
        if [[ $key = "k" ]]; then echo up; fi;
        if [[ $key = "j" ]]; then echo down; fi;
        if [[ $key = $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key = [A || $key = k ]]; then echo up;    fi;
            if [[ $key = [B || $key = j ]]; then echo down;  fi;
        fi 
    }

    toggle_option() {
        local option=$1
        if [[ ${selected[option]} == true ]]; then
            selected[option]=false
        else
            selected[option]=true
        fi
    }

    print_options() {
        # print options by overwriting the last lines
        local idx=0
        for option in "${options[@]}"; do
            local prefix="[ ]"
            if [[ ${selected[idx]} == true ]]; then
              prefix="[\e[38;5;46m✔\e[0m]"
            fi

            cursor_to $(($startrow + $idx))
            if [ $idx -eq $1 ]; then
                print_active "$option" "$prefix"
            else
                print_inactive "$option" "$prefix"
            fi
            ((idx++))
        done
    }

    local active=0
    while true; do
        print_options $active

        # user key control
        case `key_input` in
            space)  toggle_option $active;;
            enter)  print_options -1; break;;
            up)     ((active--));
                    if [ $active -lt 0 ]; then active=$((${#options[@]} - 1)); fi;;
            down)   ((active++));
                    if [ $active -ge ${#options[@]} ]; then active=0; fi;;
        esac
    done

    # cursor position back to normal
    cursor_to $lastrow
    printf "\n"
    cursor_blink_on

    eval $return_value='("${selected[@]}")'
}

function singleselectn {
  header+="\n\nPlease choose your OS, use Enter to select:\n\n"
  printf "$header"
	options=("$@")

	# helpers for terminal print control and key input
	ESC=$(printf "\033")
	cursor_blink_on()	{ printf "$ESC[?25h"; }
	cursor_blink_off()	{ printf "$ESC[?25l"; }
	cursor_to()			{ printf "$ESC[$1;${2:-1}H"; }
	print_option() { printf "\\$1 "; }
  print_selected() { printf "${COLOR_GREEN}$ESC[7m \\$1 $ESC[27m${NC}";  }
	get_cursor_row()	{ IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
  key_input() {
    local key
    # read 3 chars, 1 at a time
    for ((i=0; i < 3; ++i)); do
      read -s -n1 input 2>/dev/null >&2
      # concatenate chars together
      key+="$input"
      # if a number is encountered, echo it back
      if [[ $input =~ ^[1-9]$ ]]; then
        echo $input; return;
      # if enter, early return
      elif [[ $input = "" ]]; then
        echo enter; return;
      # if we encounter something other than [1-9] or "" or the escape sequence
      # then consider it an invalid input and exit without echoing back
      elif [[ ! $input = $ESC && i -eq 0 ]]; then
        return
      fi
    done

    if [[ $key = $ESC[A ]]; then echo up; fi;
    if [[ $key = $ESC[B ]]; then echo down; fi;
  }
  function cursorUp() { printf "$ESC[A"; }
  function clearRow() { printf "$ESC[2K\r"; }
  function eraseMenu() {
    cursor_to $lastrow
    clearRow
    numHeaderRows=$(printf "$header" | wc -l)
    numOptions=${#options[@]}
    numRows=$(($numHeaderRows + $numOptions))
    for ((i=0; i<$numRows; ++i)); do
      cursorUp; clearRow;
    done
  }

	# initially print empty new lines (scroll down if at bottom of screen)
	for opt in "${options[@]}"; do printf "\n"; done

	# determine current screen position for overwriting the options
	local lastrow=`get_cursor_row`
	local startrow=$(($lastrow - $#))
  local selected=0

	# ensure cursor and input echoing back on upon a ctrl+c during read -s
	trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
	cursor_blink_off

	while true; do
    # print options by overwriting the last lines
		local idx=0
    for opt in "${options[@]}"; do
      cursor_to $(($startrow + $idx))
      # add an index to the option
      local label="$(($idx + 1)). $opt"
      if [ $idx -eq $selected ]; then
        print_selected "$label"
      else
        print_option "$label"
      fi
      ((idx++))
    done

		# user key control
    input=$(key_input)

		case $input in
			enter) break;;
      [1-9])
        # If a digit is encountered, consider it a selection (if within range)
        if [ $input -lt $(($# + 1)) ]; then
          selected=$(($input - 1))
          break
        fi
        ;;
			up)	((selected--));
					if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi;;
			down)  ((selected++));
					if [ $selected -ge $# ]; then selected=0; fi;;
		esac
	done

  eraseMenu
	cursor_blink_on

	return $selected
}

options=("Debian / Ubuntu-based (APT)" "Fedora (DNF)"  "Arch Linux (Pacman)"  "CentOS / RHEL Based (Yum)"  "Another (Build from source)")
singleselectn "${options[@]}"
selected_os="${options[$?]}"
echo "Selected OS: $selected_os"

my_options=(   "Disable password authentication"  "Disable root account remote login"  "Limit maximum number of SSH authentication attempts"  "Change the SSH port"  "Install Fail2Ban"  "Configure IPtables for ssh security")
preselection=( "true"      "true"      "false"     "false"     "false"    "false")

echo "Use arrow keys to scroll, use space to select/deselect options, press enter to apply"
echo "-----------------------------------------------------------------------------------"

multiselect result my_options preselection


# Print the selection results
idx=0
for option in "${my_options[@]}"; do
    echo -e "$option\t=> ${result[idx]}"
    ((idx++))
done

idx=0
ssh_selected=false # Flag for ssh related options
for option in "${my_options[@]}"; do
    if [[ ${result[idx]} == "true" ]] && [[ $option =~ "authentication"|"login"|"SSH"|"port" ]]; then
        ssh_selected=true
    fi
    ((idx++))
done

echo -e "Script Execution : $(date)", "Selected OS: $selected_os" | tee -a log.txt
exec > >(tee -a log.txt) # Write the log
exec 2> >(tee -a log.txt >&2)

if $ssh_selected; then
# If any ssh-related option was selected, backup sshd_config
    echo "Backing up sshd config..." 
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
fi

echo ""

if [[ ! " ${result[@]} " =~ "true" ]]; then
    echo "Nothing to do, exiting"
    exit 0
fi

# Main loop
idx=0
for option in "${my_options[@]}"; do
    if [[ ${result[idx]} == "true" ]]; then
        case $option in
            "Disable password authentication") 
                echo "Disabling password-based authentication..."
                sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
                ;;
            "Disable root account remote login") 
                echo "Disabling root account remote login..."
                sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
                ;;
            "Limit maximum number of SSH authentication attempts") 
                echo "Limiting maximum number of SSH authentication attempts..."
                echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
                ;;
            "Change the SSH port") 
                echo "Changing the SSH port..."
                sed -i 's/#Port 22/Port 2222/g' /etc/ssh/sshd_config
                ;;
            "Install Fail2Ban") 
                echo "Installing Fail2Ban..."
                case $selected_os in
                    "CentOS / RHEL Based") 
                        yum install -y fail2ban
                        ;;
                    "Debian / Ubuntu-based") 
                        sudo apt install -y fail2ban
                        ;;
                    "Fedora")
                        dnf install -y fail2ban
                        ;;
                    "Arch Linux")
                        pacman -Sy
                        pacman -S --noconfirm fail2ban
                        ;;
                    "Another")
                        echo ">>> Need python and git to build from source"
                        git clone https://github.com/fail2ban/fail2ban.git
                        cd fail2ban
                        sudo python setup.py install
                        cd ..
                        ;;
                esac
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
                systemctl enable fail2ban
                systemctl start fail2ban
                ;;
            "Configure IPtables for ssh security") 
                echo ">>> Backing up iptables rules..."
                cp /etc/iptables/iptables.rules /etc/iptables/iptables.rules.bak
                cp /etc/iptables/ip6tables.rules /etc/iptables/ip6tables.rules.bak

                echo ">>> Applying SSH rate control security rules..."
                iptables -I INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
                iptables -I INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 120 --hitcount 10 -j DROP

                ip6tables -I INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
                ip6tables -I INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 120 --hitcount 10 -j DROP

                echo ">>> Saving the new iptables rules..."
                iptables-save > /etc/iptables/iptables.rules
                ip6tables-save > /etc/iptables/ip6tables.rules

                echo ">>> Making the iptables configuration persistent..."
                sudo sh -c "echo 'iptables-restore < /etc/iptables/iptables.rules' >> /etc/rc.local"
                sudo sh -c "echo 'ip6tables-restore < /etc/iptables/ip6tables.rules' >> /etc/rc.local"

                echo ">>> SSH rate control configured successfully!"
                ;;
        esac
    fi
    ((idx++))
done

systemctl restart sshd

echo "SSH Hardening complete! Backed up data to /Backup folder, output log in log.txt"
echo ""