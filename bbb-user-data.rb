#!/usr/bin/ruby

#
# BlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2018 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#
# bbb-user-data.rb
#

require 'trollop'
require 'nokogiri'
require 'csv'
require 'terminal-table'
# require '/usr/local/bigbluebutton/core/lib/recordandplayback'

# opts = Trollop.options do
#   opt :userId, 'userId', type: :string
#   opt :recordingPath, 'recordingPath', type: :string
# end

$current_presenter = 'unknown'
$copy_audio_list = []
$recording_start
$audioFile
$endspeaking

def get_user_info(userid, dirid)
  rows = []
  $recording_start = 0
  meeting_end = 0
  CSV.open("#{userid}/info.csv", 'a+') do |csv|
    # Search in all directories for a file of name events.xml
    csv << []
    csv << ["Info in database for user with ID(#{userid})"]
    csv << ["From Dir: #{dirid}"]
    csv << ['event', 'timestamp', 'module', 'Msg (if applicable)']
    puts "User: #{userid}\tDirectory: #{dirid}"
    Dir.glob("#{dirid}/events.xml") do |file|
      doc = Nokogiri::XML(File.open(File.expand_path(file)))
      events = doc.xpath('//event')
      meeting_end = Integer(events.last.at_xpath('@timestamp').to_s)
      handle_events(csv, userid, events, rows, dirid)
    end
  end
  display_table(userid, rows)
  puts "user info's generated. Path: #{Dir.pwd}/info.csv"
  copy_audio(userid, dirid, meeting_end - $recording_start, meeting_end)
end

def display_table(user_id, rows)
  # rows << "data concerning user with Id: #{user_id}"
  table = Terminal::Table.new title: "Info for user with id: #{user_id}", headings: %w[event timestamp module], rows: rows
  puts table
end

def get_data(csv, userid, dirid)
  Dir.glob("#{dirid}/events.xml") do |file|
    doc = Nokogiri::XML(File.open(File.expand_path(file)))
    events = doc.xpath('//event')
    handle_events(csv, userid, events, rows, dirid)
  end
end

def handle_events(csv, userid, events, rows, directory)
  meeting_start = Integer(events.first.at_xpath('@timestamp').to_s)
  events.each do |e|
    e_module = e.at_xpath('@module').to_s
    t_stamp = f_time(Integer(e.at_xpath('@timestamp').to_s) - meeting_start)
    e_name = e.at_xpath('@eventname').to_s
    e_name.eql?('SharePresentationEvent') && $current_presenter == userid && copy_presentation(e.at_xpath('presentationName').content.to_s, directory, userid)
    e_name.eql?('AssignPresenterEvent') && user?(e, userid) && $current_presenter = userid
    e_name.eql?('DeskshareStartedEvent') && $current_presenter == userid && copy_deskshare(userid, "#{directory}/deskshare/#{e.at_xpath('stream').content.to_s}")
    e_name.eql?('StartRecordingEvent') && $recording_start = Integer(e.at_xpath('recordingTimestamp').content.to_s) && $endspeaking = $recording_start
    user?(e, userid) && e_name.eql?('ParticipantTalkingEvent') && registerParticipantTalkingEvent(e, directory)
    next if %w[PRESENTATION WHITEBOARD].include? e_module
    user?(e, userid) && handle_event(e, e_name, t_stamp, e_module, csv, rows)
  end
end

def f_time(time)
  Time.at(time / 1000).utc.strftime('%H:%M:%S')
end

def handle_event(event, e_name, t_stamp, e_module, csv, rows)
  csv << if e_module.eql? 'CHAT'
           [e_name, t_stamp, e_module, event.at_xpath('message').content.to_s.strip]
         else
           [e_name, t_stamp, e_module]
         end
  rows << [e_name, t_stamp, e_module]
end

def user?(event, user_id)
  e_name = event.at_xpath('@eventname').to_s
  if %w[StopWebcamShareEvent StartWebcamShareEvent].include? e_name
    e_stream = event.at_xpath('stream').content.to_s
    return e_stream.include? user_id
  end
  userid = event.at_xpath('userId')
  userid.nil? && userid = event.at_xpath('userid')
  userid.nil? && userid = event.at_xpath('senderId')
  userid.nil? && userid = event.at_xpath('participant')
  userid.nil? ? false : userid.content == user_id
end

def check_file_exist(pathtofile)
  File.exist?("#{pathtofile}/events.xml")
end

def copy_video(user_id, directory)
  Dir.glob("#{directory}/video/*/*.flv") do |videofile|
    videofile.include?(user_id) && system("cp #{videofile} #{user_id}/videos/")
  end
end

def copy_deskshare(user_id, stream_dir)
    Dir.glob("#{stream_dir}.*") do |desk_file|
        system("cp -r #{desk_file} #{user_id}/deskshare/")
    end
end

def copy_presentation(presentationfile, directory, user_id)
  system("cp -r #{directory}/presentation/#{presentationfile} #{user_id}/presentation/") && puts("#{presentationfile} copied.")
end

def registerParticipantMutedEvent(event, directory)
  true?(event.at_xpath('muted').content.to_s) && return
  e_timestamp = (Integer(event.at_xpath('@timestamp').to_s) - $recording_start)
  Dir.glob("#{directory}/audio/*.wav") do |audiofile|
    puts "req -r audio: [#{f_time($endspeaking)}, #{f_time(e_timestamp)}]"
    $audioFile = audiofile
    $copy_audio_list.push(make_audio_removal_request($endspeaking.to_s, e_timestamp.to_s))
  end
  $endspeaking = e_timestamp
end

def registerParticipantTalkingEvent(event, directory)
  e_timestamp = (Integer(event.at_xpath('@timestamp').to_s) - $recording_start)
  if true?(event.at_xpath('talking').content)
    Dir.glob("#{directory}/audio/*.wav") do |audiofile|
      puts "req -r audio: [#{f_time($endspeaking)}, #{f_time(e_timestamp)}]"
      $audioFile = audiofile
      $copy_audio_list.push(make_audio_removal_request($endspeaking.to_s, e_timestamp.to_s))
    end
  else
    $endspeaking = e_timestamp
  end
end

def true?(obj)
  obj.to_s == 'true'
end

def f_time(time)
  Time.at(time / 1000).utc.strftime('%H:%M:%S')
end

def copy_audio(user_id, dirname, meetingDuration, meeting_end)
  if $audioFile.nil? || $copy_audio_list.nil? || $copy_audio_list.empty?
    puts('No audio file present or no recording of the user are in this file.\n No audio has been removed')
    return
  end
  total_time = 0
  command = ['ffmpeg', '-i', $audioFile, '-af']
  filter = "volume=volume=0:enable='"

  loop do
    filter += 'between(t\\,' + $copy_audio_list.first[:start]
    filter += '\\,' + $copy_audio_list.first[:finish] + ')'
    total_time += Integer($copy_audio_list.first[:finish]) - Integer($copy_audio_list.first[:start])
    $copy_audio_list.shift
    filter += '+'
    $copy_audio_list.empty? && break
  end
  filter += 'between(t\\,' + $endspeaking.to_s
  filter += '\\,' + meeting_end.to_s + ')'
  filter += "'"
  total_time += Integer($endspeaking) - Integer(meeting_end)
    
  command << filter
  command << '-y'
  command << 'temp.wav'
  system(*command)
  FileUtils.mv 'temp.wav', "#{user_id}/audio/#{File.basename(dirname)}.wav"
  puts 'All audio recordings have been editted and copied'
  puts "Recording total time: #{f_time(meetingDuration)} ."
  puts "Total time muted: #{f_time(total_time)} ."
end

def make_audio_removal_request(start, finish)
  { start: start, finish: finish }
end

def bbb_user_data(userId,recordingPath)
  if userId.nil? || recordingPath.nil?
    puts 'please provide userId and recording ID like so:'
    puts './bbb-user-data -u <userID> -r <recordingPath>'
  elsif check_file_exist(recordingPath.chomp('/'))
       get_user_info(userId, recordingPath.chomp('/'))
    copy_video(userId, recordingPath.chomp('/'))
    # system ("zip -r #{userId}.zip #{userId}; rm -r #{userId}")
  else
    puts "The path you provided does not exist.\n Path: #{recordingPath}"
  end
end