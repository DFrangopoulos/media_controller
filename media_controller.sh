#!/bin/bash
#v1.0.6

self_path="$0"

flexget_config="/home/$(whoami)/.config/flexget/config.yml"
audio_playlist="/home/$(whoami)/playlist.xml"

flexget_bin="/home/$(whoami)/.local/bin/flexget"
tcp_daemon="/home/$(whoami)/.local/bin/yt_tcp_daemon"
yt_downloader_bin="/home/$(whoami)/.local/bin/yt-dlp_linux"

yt_folder_subs="/home/$(whoami)/YT_Subs"
yt_folder_ones="/home/$(whoami)/YT_Ones"
yt_folder_ones_audio="/home/$(whoami)/YT_Ones_Audio"
yt_folder_archive="/home/$(whoami)/YT_Archive"

sub_list="/home/$(whoami)/yt_sub_list.txt"
one_list="/home/$(whoami)/yt_one_list.txt"
tmp_cron_list="/tmp/cronlist"

tmp_name() {
  echo "/tmp/$(head -c100 /dev/urandom | md5sum | sed -r 's/[^a-z0-9]//g').tmp"
}

format_file() {
  if [ -f "$1" ]
  then
    test "$(tail -c1 "$1" | xxd -p | head -c2)" = "0a" || echo "" >> "$1"
  fi
}

extract_current_sub_list() {
  grep "channel_id" "$flexget_config" | sed -r 's/.*(https.*)/\1/' > "$sub_list"
}

update_current_sub_list() {
  echo "https://www.youtube.com/feeds/videos.xml?channel_id=$1" >> "$sub_list"
  sort -u "$sub_list" -o "$sub_list"
}

generate_flexget_yml()
{
  # only run if the yt_list exists
  if [ -f "$sub_list" ]
  then
    #wipe the exiting yml config
    > "$flexget_config"
    #ensure last line in newline terminated
    format_file "$sub_list"
    #create header
    echo "tasks:" >> "$flexget_config"

    #process list
    count=0
    while read line
    do
      echo "  youtube-$(printf "%03d" $count):" >> "$flexget_config"
      echo "    rss: $line">> "$flexget_config"
      echo "    accept_all: true" >> "$flexget_config"
      echo "    exec: $yt_downloader_bin --dateafter now-7days -f 'bestvideo[ext=mp4][height<1200]+bestaudio[ext=m4a]' --embed-thumbnail --convert-thumbnails png --restrict-filenames --merge-output-format mkv -o \"$yt_folder_subs/%(uploader)s_%(upload_date>%Y-%m-%d)s_%(title)s_%(id)s.%(ext)s\" \"{{url}}\"" >> "$flexget_config"
      count=$(($count + 1))
    done < <(cat "$sub_list")
    rm "$sub_list"
  fi
}

fetch_one_shot() {
  if [ -n "$1" ]
  then
    $yt_downloader_bin -f 'bestvideo[ext=mp4][height<1200]+bestaudio[ext=m4a]' --embed-thumbnail --convert-thumbnails png --restrict-filenames --merge-output-format mkv -o "$yt_folder_ones/%(uploader)s_%(title)s_%(upload_date>%Y-%m-%d)s_%(id)s.%(ext)s" "$1" || return 1
  fi
}

fetch_one_shot_list() {
  if [ -f "$one_list" ]
  then
    #ensure last line in newline terminated
    format_file "$one_list"
    while read url
    do
      fetch_one_shot "$url"
    done < <(cat "$one_list")
    rm "$one_list"
  fi
}

yt_archive() {
  #archive videos older that 3 days
  find "$yt_folder_subs" -maxdepth 1 -type f -ctime +3 -print | xargs -I{} mv "{}" "$yt_folder_archive"
}

refresh_folders() {
  test -d "$yt_folder_subs" || mkdir "$yt_folder_subs"
  test -d "$yt_folder_ones" || mkdir "$yt_folder_ones"
  test -d "$yt_folder_archive" || mkdir "$yt_folder_archive"
  test -d "$yt_folder_ones_audio" || mkdir "$yt_folder_ones_audio"
}

trigger_subs() {
  $flexget_bin execute --tasks "youtube-*"
}

convert_ones_to_audio() {
  for file in "$yt_folder_ones"/*
  do
    if [ -f "$file" ]
    then
      new_file="$yt_folder_ones_audio/$(basename "$file" | rev | sed -r 's/[^.]+(.*)/\1/' | rev)m4a"
      echo "Processing $file"
      if [ ! -f "$new_file" ]
      then
        ffmpeg -i "$file" -vn -acodec copy "$new_file"
      else
        echo "$new_file already exists!"
      fi
    fi
  done
}

run_tcp_daemon() {
  result="$(ps -aux | grep "$(basename "$tcp_daemon")" | grep -v "grep")"
  if [ -z "$result" ]
  then
    echo "Starting tcp daemon"
    nohup "$tcp_daemon" &
  else
    echo "Tcp daemon already running!"
  fi
}

is_self_running() {
  #TODO Rework
  result="$(ps -aux | grep "$(basename "$self_path")" | grep -v "grep" | wc -l)"
  if [ "$result" -gt 3 ]
  then
    echo "Another media controller is already running! There can only be one! Exiting..."
    exit 1
  fi
}

regen_audio_playlist() {
  tmp_file=$(tmp_name)
  grep -B100 "<PlaylistItems>" "$audio_playlist" >> "$tmp_file"
  for file in "$yt_folder_ones_audio"/*
    do
      if [ -f "$file" ]
      then
        echo "    <PlaylistItem>" >> "$tmp_file"
        echo "      <Path>$(realpath "$file")</Path>" >> "$tmp_file"
        echo "    </PlaylistItem>" >> "$tmp_file"
      fi
  done
  grep -A100 "</PlaylistItems>" "$audio_playlist" >> "$tmp_file"
  mv "$tmp_file" "$audio_playlist"
}

###CASES###

help() {
  echo "Invalid option!"
  exit 0
}

install() {
  echo "Installing..."

  #Check deps
  test -f "$flexget_bin" || (echo "Flexget not found"; exit 1)
  test -f "$tcp_daemon" || (echo "TCP daemon not found"; exit 1)
  test -f "$yt_downloader_bin" || (echo "YT downloader not found"; exit 1)
  which ffmpeg || (echo "Ffmpeg not found"; exit 1)

  tmp_file=$(tmp_name)
  crontab -l > "$tmp_file"
  echo "00 * * * * $(realpath "$0") execute" >> "$tmp_file"
  sort -u "$tmp_file" -o "$tmp_cron_list"
  crontab "$tmp_cron_list"
  crontab -l
  rm "$tmp_file" "$tmp_cron_list"
}

uninstall() {
  echo "Uninstalling..."
  tmp_file=$(tmp_name)
  crontab -l > "$tmp_file"
  grep -v "$(realpath "$0")" "$tmp_file" > "$tmp_cron_list"
  crontab "$tmp_cron_list"
  crontab -l
  rm "$tmp_file" "$tmp_cron_list"
}

add_subscription() {
  if [ -z "$1" ]
  then
    echo "Please specify YT channel id!"
    exit 1
  fi
  #Update flexget
  extract_current_sub_list
  update_current_sub_list "$1"
  generate_flexget_yml
}

execute() {
  #Update lists
  generate_flexget_yml
  #Create folders
  refresh_folders
  #Fetch subs
  trigger_subs
  #Fetch ones
  fetch_one_shot_list
  #Convert ones to audio
  convert_ones_to_audio
  #Update audio playlist
  regen_audio_playlist
  #Archive subs
  #yt_archive
  #Ensure tcp daemon is running
  run_tcp_daemon
}

###MAIN###

#Select mode
case "$1" in

  "help")
    is_self_running
    help
    ;;

  "install")
    is_self_running
    install
    ;;

  "uninstall")
    is_self_running
    uninstall
    ;;

  "add")
    is_self_running
    add_subscription "$2"
    ;;

  "fetch")
    is_self_running
    fetch_one_shot "https://www.youtube.com/watch?v=$2" || exit 1
    ;;

  "execute")
    is_self_running
    execute
    ;;

  *)
    is_self_running
    help
    ;;
esac

exit 0