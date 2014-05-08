if ARGV.empty?
  puts "ERROR: missing arguments
usage: ruby #{$0} file [output]
\tfile\tthe file to scan; could be a regular file, disc image or block device
\toutput\t(optional) directory to save extracted files to. Default value is ./jpeg-files"
  exit 1
end
READ_BUFFER_SIZE = 1024 * 1024 * 10
file_path = ARGV[0]

file = File.open(file_path)
file_size = File.size(file_path)
output_dir = ARGV[1] || './jpeg-files'
output_dir = output_dir.sub(/(.+)\/$/,'\1')
Dir.mkdir("#{output_dir}") if not Dir.exists?("#{output_dir}")

class JpegExtractor
  RANDOM = Random.new
  HEADERS = "\xC0\xC2\xC4\xDB\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xFE\xDD".unpack('C*')
  RSTn = "\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7".unpack('C*')
  MARKER = 0xFF
  SOI = 0xD8
  SOS = 0xDA
  EOI = 0xD9
  NULL = 0x00
  attr_reader :files_extracted

  def initialize(source, target)
    @source = source
    @target = target
    @bytes_to_skip = 0
    @byte_buffer = "".force_encoding("ASCII-8BIT")
    @files_extracted = 0
    @has_marker = false
    @has_SOI = false
    @has_SOS = false
    @has_header = false
    @header_size_one = nil
    @header_size_two = nil
  end
  def skip_byte
    @bytes_to_skip -= 1
    reset_header if @bytes_to_skip == 0
  end
  def extract
    @extracting = true
    @file_name = RANDOM.bytes(16).unpack('H*')[0]
    IO.write("#{@target}/#{@file_name}.jpg", @byte_buffer)
    @extracting = false
    @files_extracted += 1
    reset
  end
  def reset
    @byte_buffer.clear
    @has_marker = false
    @has_SOI = false
    @has_SOS = false
  end
  def reset_header
    @has_header = false
    @header_size_one = nil
    @header_size_two = nil
  end
  def did_extract
    return @file_name if @file_name
    return false
  end
  def <<(byte)
    @file_name = nil
    if @bytes_to_skip > 0
      skip_byte
      @byte_buffer << byte
    elsif @has_header
      if @header_size_one != nil
        if @header_size_two != nil
          @bytes_to_skip = (@header_size_one << 8 | @header_size_two) - 3 # minus 3 because 2 bytes are the size, 1 more because we've already read it.
          @byte_buffer << byte
        else
          @header_size_two = byte
          @byte_buffer << byte
        end
      else
        @header_size_one = byte
        @byte_buffer << byte
      end
    elsif @has_marker
      if @has_SOI
        if HEADERS.include? byte
          @has_header = true
          @byte_buffer << byte
        elsif byte == SOS
          @has_SOS = true
          @byte_buffer << byte
        elsif @has_SOS # should this come before byte == SOS ?
          if byte == EOI
            @byte_buffer << byte
            extract
          elsif byte == SOI # duplicate SOI
            @byte_buffer << byte
            @byte_buffer = @byte_buffer[-2..-1]
          elsif byte == NULL || RSTn.include?(byte)
            # escaped FF byte or reset flag, ignore this
            @byte_buffer << byte
          else # unexpected byte
            reset
          end
        elsif byte == SOI
          @byte_buffer << byte
          # duplicate SOI, false positive or partial jpeg, abandon current search and start over
          @byte_buffer = @byte_buffer[-2..-1]
        else
          # unexpected byte
          reset
        end
      elsif byte == SOI
        @byte_buffer << byte
        @has_SOI = true
      else
        reset
      end
      @has_marker = false
    elsif byte == MARKER
      @byte_buffer << byte
      @has_marker = true
    elsif @has_SOS
      @byte_buffer << byte
    else
      reset
    end
  end
  def status
    "#{has_marker ? 'Marker' : ''} #{has_SOI ? 'SOI' : ''} #{has_SOS ? 'SOS' : ''}"
  end
end

def time_string(seconds)
  h = (seconds / 3600).to_i
  m = ((seconds - (h * 3600)) / 60).to_i
  s = (seconds - (h * 3600) - (m * 60)).to_i
  "%02d:%02d:%02d" % [h,m,s]
end

jpeg = JpegExtractor.new(file_path, output_dir)
start_time = Time.now
file_pos = 0

begin
  while read_buffer = file.read(READ_BUFFER_SIZE)
    read_buffer.each_byte do |buffered_byte|
      file_pos += 1
      jpeg << buffered_byte
      # printing status is expensive, do so sparingly
      if file_pos == 1 || file_pos % 1024 == 0 || file_pos == file_size
        et = (Time.now - start_time)
        speed = (file_pos / et)
        rt = (file_size - file_pos) / speed
        print "\r%.2f%% %d files -%s +%s %.2f kB/s" % 
            [((file_pos.to_f/file_size)*100).round(2), jpeg.files_extracted, time_string(et), time_string(rt), (speed / 1024).to_s]
      end
    end
  end
rescue Interrupt
  puts "\nCanceled"
  exit 1
rescue => error
  puts error.message
  puts error.backtrace.join("\n")
ensure
  file.close
end

puts "\n"