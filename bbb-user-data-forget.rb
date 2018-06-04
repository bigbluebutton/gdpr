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
# bbb-user-data-forget.rb
#

require 'nokogiri'
require 'csv'
require 'fileutils'
require 'terminal-table'

$removalList = []
$audioFile
$meetingStart
$start_speaking
$dry

def delUserInfo(user_id, dir_id)
  if user_id.nil?
    puts 'You did not specify an id.'
    puts 'Please provide an id as an argument before you run this script'
    exit
  end
  recording_start = 0
  meeting_end = 0
  $start_speaking = 0
  current_presenter = 'unknown'
  rows = []
  rows << %w[event user_Id module removed start end]

  Dir.glob("#{dir_id}/events.xml") do |file|
    doc = Nokogiri::XML(File.open(File.expand_path(file)))
    events = doc.xpath('//event')
    meeting_start = Integer(events.first.at_xpath('@timestamp').to_s)
    meeting_end = Integer(events.last.at_xpath('@timestamp').to_s)
    directory = File.dirname(File.absolute_path(file))
    events.each do |event|
      dry? && next if %w[WHITEBOARD].include? event.at_xpath('@module').to_s
      e_name = event.at_xpath('@eventname').to_s
      if e_name.eql? 'StartRecordingEvent'
        recording_start = Integer(event.at_xpath('recordingTimestamp').content.to_s)
        display_event(event, rows, '', 'start Recording at: ', f_time(recording_start - meeting_start))
        next
      elsif e_name.eql? 'AssignPresenterEvent'
        current_presenter = event.at_xpath('userid').content.to_s
      elsif %w[ResizeAndMoveSlideEvent GotoSlideEvent].include? e_name
        if current_presenter == user_id
          remove_event(event, rows, directory, recording_start, meeting_start)
          next
        end
      elsif e_name.eql? 'SharePresentationEvent'
        if current_presenter == user_id
          pres_dir = event.at_xpath('presentationName').content.to_s
          if dry?
            puts "presentation folder to be deleter #{pres_dir}"
            display_event(event, rows, 'X')
          else
            system("rm -r #{directory}/presentation/#{pres_dir}")
            puts "presentation file #{directory}/presentation/#{pres_dir} deleted."
            remove_event(event, rows, directory, recording_start, meeting_start)
          end
          next
        end
      elsif e_name.eql? 'DeskshareStartedEvent'
        if current_presenter == user_id
          stream_dir = event.at_xpath('stream').content.to_s
          Dir.glob("#{directory}/deskshare/#{stream_dir}.*") do |desk_file|
            if dry?
              puts "deskshare file to be deleted : #{desk_file}"
              display_event(event, rows, 'X')
            else
              system("rm -r #{desk_file}")
              puts "Deskshare file #{directory}/presentation/#{stream_dir} deleted."
              remove_event(event, rows, directory, recording_start, meeting_start)
            end
          end
          next
        end
      elsif %w[PollStartedRecordEvent PollStoppedRecordEvent UserRespondedToPollRecordEvent].include? e_name
        if current_presenter == user_id
          if dry?
            display_event(event, rows, 'X')
          else
            remove_event(event, rows, directory, recording_start, meeting_start)
          end
        end
        next
      end
      unless user?(event, user_id)
        dry? && display_event(event, rows, '')
        next
      end
      if e_name.eql? 'ParticipantJoinEvent'
        e_stamp = event.at_xpath('@timestamp').to_s
        $start_speaking = (Integer(e_stamp) - recording_start)
      end
      remove_event(event, rows, directory, recording_start, meeting_start)
    end
    File.open(File.expand_path(file), 'w') { |f| doc.write_xml_to f }
    remove_video(user_id, directory)
  end
  puts dry? ? 'Dry run' : 'Data removal run'
  puts "data concerning user with Id: #{user_id}"
  table = Terminal::Table.new title: 'Info', headings: ["id: #{user_id}"], rows: rows
  puts table
  remove_audio(meeting_end - recording_start)
end

def user?(event, user_id)
  e_name = event.at_xpath('@eventname').to_s
  if %w[StopWebcamShareEvent StartWebcamShareEvent].include? e_name
    e_stream = event.at_xpath('stream').content.to_s
    return e_stream.include? user_id
  end
  get_uid(event) == user_id
end

def get_uid(event)
  userid = event.at_xpath('userId')
  userid.nil? && userid = event.at_xpath('userid')
  userid.nil? && userid = event.at_xpath('senderId')
  userid.nil? && userid = event.at_xpath('participant')
  userid.nil? ? 'unkown' : userid.content
end

def true?(obj)
  obj.to_s == 'true'
end

def f_time(time)
  Time.at(time / 1000).utc.strftime('%H:%M:%S')
end

def remove_audio_event(event)
  event.remove
end

def remove_video(user_id, directory)
  Dir.glob("#{directory}/video/*/*.flv") do |videofile|
    videofile.include?(user_id) && !dry? && system("rm #{videofile}") && puts("#{videofile} removed.")
  end
end

def make_audio_removal_request(start, finish)
  { start: start, finish: finish }
end

def dry?
  $dry
end

def remove_audio(meetingDuration)
  if $audioFile.nil? || $removalList.empty?
    puts("No audio file present.\n No audio has been removed")
    return
  end
  total_time = 0
  command = ['ffmpeg', '-i', $audioFile, '-af']
  filter = "volume=volume=0:enable='"

  loop do
    filter += 'between(t\\,' + $removalList.first[:start]
    filter += '\\,' + $removalList.first[:finish] + ')'
    total_time += Integer($removalList.first[:finish]) - Integer($removalList.first[:start])
    $removalList.shift
    $removalList.empty? && break
    filter += '+'
  end
  filter += "'"

  command << filter
  command << '-y'
  command << 'temp.wav'
  if dry?
    puts "command that was going to run: \n#{command.join(' ')}"
  else
    system(*command)
    FileUtils.mv 'temp.wav', $audioFile
    puts 'All audio recordings have been removed'
  end
  puts "Recording total time: #{f_time(meetingDuration)} ."
  puts "Total time muted: #{f_time(total_time)} ."
end

def removeParticipantMutedEvent(event, rows, directory, recording_start)
  !true?(event.at_xpath('muted').content.to_s) && return
  e_timestamp = (Integer(event.at_xpath('@timestamp').to_s) - recording_start)
  Dir.glob("#{directory}/audio/*.wav") do |audiofile|
    puts "req -r audio: [#{f_time($start_speaking)}, #{f_time(e_timestamp)}]"
    $audioFile = audiofile
    $removalList.push(make_audio_removal_request($start_speaking.to_s, e_timestamp.to_s))
  end
  display_event(event, rows, 'X', 'mic muted:', f_time(e_timestamp))
  $start_speaking = e_timestamp
  !dry? && remove_audio_event(event)
end

def removeParticipantTalkingEvent(event, rows, directory, recording_start)
  e_timestamp = (Integer(event.at_xpath('@timestamp').to_s) - recording_start)
  if true?(event.at_xpath('talking').content)
    $start_speaking = e_timestamp
    display_event(event, rows, 'X', 'mic on:', f_time(e_timestamp))
  else
    Dir.glob("#{directory}/audio/*.wav") do |audiofile|
      puts "req -r audio: [#{f_time($start_speaking)}, #{f_time(e_timestamp)}]"
      $audioFile = audiofile
      $removalList.push(make_audio_removal_request($start_speaking.to_s, e_timestamp.to_s))
    end
    display_event(event, rows, 'X', 'mic off:', f_time(e_timestamp))
    $start_speaking = e_timestamp
  end
  !dry? && remove_audio_event(event)
end

def remove_event(event, rows, directory, r_start, meeting_start)
  !dry? && event.remove
  e_module = event.at_xpath('@module')
  e_name = event.at_xpath('@eventname').to_s
  e_timestamp = Integer(event.at_xpath('@timestamp').to_s)
  return if ['WHITEBOARD'].include? e_module.to_s
  if e_name.eql? 'ParticipantJoinEvent'
    return display_event(event, rows, 'X', 'user joined at: ', f_time(e_timestamp - meeting_start))
  end
  e_name.eql?('ParticipantMutedEvent') && removeParticipantMutedEvent(event, rows, directory, r_start)
  e_name.eql?('ParticipantTalkingEvent') && removeParticipantTalkingEvent(event, rows, directory, r_start)
  display_event(event, rows, 'X')
end

def display_event(event, rows, delete, start = '', finish = '')
  e_name = event.at_xpath('@eventname')
  e_module = event.at_xpath('@module')
  rows << [e_name, get_uid(event), e_module, delete, start, finish]
end

def check_file_exist(pathtofile)
  File.exist?("#{pathtofile}/events.xml")
end

def bbb_user_data_forget(userId, recordingPath, dry)
  $dry = dry
  if userId.nil? || recordingPath.nil?
    puts 'please provide userId and recording path like so:'
    puts './bbb-user-data-forget -u <userID> -r <recordingPath>'
  elsif check_file_exist(recordingPath.chomp('/'))
    delUserInfo(userId, recordingPath.chomp('/'))
  else
    puts "The path you provided does not exist.\n Path: #{recordingPath}"
  end
end
