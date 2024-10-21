#!/bin/bash

valid_cidr() {
  local cidr="$1"
  if [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    return 0
  else
    echo "Invalid CIDR format. Use format like 10.10.110.0/24"
    exit 1
  fi
}


cidr_to_netmask() {
  local cidr="$1"
  local ip=$(echo $cidr | cut -d/ -f1)
  local prefix=$(echo $cidr | cut -d/ -f2)

  ipcalc_output=$(ipcalc -n -b "$cidr")
  network_address=$(echo "$ipcalc_output" | grep Network | awk '{print $2}')
  broadcast_address=$(echo "$ipcalc_output" | grep Broadcast | awk '{print $2}')

  echo "$network_address $broadcast_address"
}


ip_to_int() {
  local ip="$1"
  local a b c d
  IFS=. read -r a b c d <<< "$ip"
  echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ip() {
  local int="$1"
  echo "$((int >> 24 & 255)).$((int >> 16 & 255)).$((int >> 8 & 255)).$((int & 255))"
}

ping_sweep() {
  local cidr="$1"

  valid_cidr "$cidr"

 
  local net_broadcast=($(cidr_to_netmask "$cidr"))
  local network_address="${net_broadcast[0]}"
  local broadcast_address="${net_broadcast[1]}"

  
  local start_ip=$(ip_to_int "$network_address")
  local end_ip=$(ip_to_int "$broadcast_address")

  # Subnet prefix to get file name (e.g., 10.10.110.0/24 -> result_10.10.110.0_24_scan.txt)
  local subnet_prefix="${cidr//\//_}"
  local result_file="result_${subnet_prefix}_scan.txt"

  
  [ -f "$result_file" ] && rm "$result_file"

 
  echo "Starting ping sweep on $cidr..."
  for ((ip=start_ip+1; ip<end_ip; ip++)); do
    current_ip=$(int_to_ip "$ip")
    (ping -c 1 -W 1 "$current_ip" | grep "bytes from" > /dev/null && echo "$current_ip" >> "$result_file" &)
  done

  wait  

  echo "Ping sweep completed. Live IPs saved to $result_file."

  
  if [ -s "$result_file" ]; then
    perform_nmap_scan "$result_file" "$subnet_prefix"
  else
    echo "No live hosts found in the ping sweep. Skipping Nmap scan."
  fi
}


perform_nmap_scan() {
  local result_file="$1"
  local subnet_prefix="$2"
  local nmap_output="full_scan_${subnet_prefix}"

  echo "Starting Nmap scan on live hosts..."
  nmap -sSCV -Pn -p- -iL "$result_file" -vvv -oA "$nmap_output"

  echo "Nmap scan completed. Results saved as ${nmap_output}.*"
}


if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <subnet in CIDR notation (e.g., 10.10.110.0/24)>"
  exit 1
fi
subnet="$1"


ping_sweep "$subnet"
