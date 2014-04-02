if ARGV.empty?
  puts "ERROR: missing arguments
usage: ruby #{$0} file [output]
\tfile\tthe file to scan; could be a regular file, disc image or block device
\toutput\t(optional) directory to save extracted files to. Default value is ./jpeg-files"
  exit 1
end
file_path = ARGV[0]

file = File.open(file_path)
file_size = File.size(file_path)
output_dir = ARGV[1] || './jpeg-files'
output_dir = output_dir.sub(/(.+)\/$/,'\1')
Dir.mkdir("#{output_dir}") if not Dir.exists?("#{output_dir}")

class Byte
  HEADERS = "\xC0\xC2\xC4\xDB\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xFE\xDD".unpack('C*')
  RSTn = "\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7".unpack('C*')
  attr_accessor :value
  def initialize(value)
    @value = value
  end
  def to_s
    "%02X" % @value
  end
  def is_marker
    return true if @value == 0xFF
    false
  end
  def is_SOI
    return true if @value == 0xD8
    false
  end
  def is_SOS
    return true if @value == 0xDA
    false
  end
  def is_EOI
    return true if @value == 0xD9
    false
  end
  def is_NULL
    return true if @value == 0x00
    false
  end
  def is_header
    return true if HEADERS.include?(@value)
    false
  end
  def is_scan_reset
    return true if RSTn.include?(@value)
    false
  end
end

class JpegExtractor
  @files_extracted = 0
  attr_accessor :start_offset, :end_offset, :has_marker, :has_SOI, :has_SOS
  attr_reader :files_extracted, :is_extracting
  @source = nil
  @target = nil
  def initialize(source, target)
    @source = source
    @target = target
    @files_extracted = 0
  end
  def length
    @end_offset - @start_offset
  end
  def extract
    @extracting = true
    IO.write("#{@target}/#{@start_offset.to_s}.jpg", IO.read(@source, self.length, self.start_offset))
    @extracting = false
    @files_extracted += 1
    reset
  end
  def reset
    @start_offset = nil
    @end_offset = nil
    @has_marker = false
    @has_SOI = false
    @has_SOS = false
  end
  def status
    "#{has_marker ? 'Marker' : ''} #{has_SOI ? 'SOI' : ''} #{has_SOS ? 'SOS' : ''} #{is_extracting ? 'Extracting' : ''}"
  end
end

def time_string(seconds)
  h = (seconds / 3600).to_i
  m = ((seconds - (h * 3600)) / 60).to_i
  s = (seconds - (h * 3600) - (m * 60)).to_i
  "%02d:%02d:%02d" % [h,m,s]
end

byte = Byte.new(-1)
jpeg = JpegExtractor.new(file_path, output_dir)
start_time = Time.now

begin
  while read_buffer = file.read(1)
    should_update_status = false
    byte.value = read_buffer.unpack('C')[0]
    if jpeg.has_marker
      if jpeg.has_SOI
        if byte.is_header
          x = file.read(2).unpack('CC')
          length = x[0] << 8 | x[1]
          file.seek(length-2, IO::SEEK_CUR)
        elsif byte.is_SOS
          jpeg.has_SOS = true
        elsif jpeg.has_SOS
          if byte.is_EOI
            jpeg.end_offset = file.pos
            if jpeg.length > 0
              jpeg.extract
              should_update_status = true
            else
              puts "ERROR, cannot extract zero or negative size: SOF=#{jpeg.start_offset} EOF=#{jpeg.end_offset}"
            end
            jpeg.reset
          elsif byte.is_SOI # duplicate SOI
            jpeg.start_offset = file.pos - 2
          elsif byte.is_NULL || byte.is_scan_reset
            # esacped FF byte or reset flag, ignore this
          else # unexpected byte
            jpeg.reset
          end
        elsif byte.is_SOI
          # duplicate SOI, false positive or partial jpeg, abandon current search and start over
          jpeg.start_offset = file.pos - 2
        else
          # unexpected byte
          jpeg.reset
        end
      elsif byte.is_SOI
        jpeg.has_SOI = true
        jpeg.start_offset = file.pos - 2
      else
        jpeg.reset
      end
      jpeg.has_marker = false
    elsif byte.is_marker
      jpeg.has_marker = true
    elsif jpeg.has_SOS
      # do nothing
    else
      jpeg.reset
    end
    # don't slow down script by printing status on every byte
    if should_update_status || file.pos == 1 || file.pos % 10240 == 0 || file.pos == file_size
      et = (Time.now - start_time)
      speed = (file.pos / et)
      rt = (file_size - file.pos) / speed
      print "\r%.2f%% %d files -%s +%s %.2f kB/s" % 
          [((file.pos.to_f/file_size)*100).round(2), jpeg.files_extracted, time_string(et), time_string(rt), (speed / 1024).to_s]
    end
  end
rescue => error
  puts error.message
  puts error.backtrace.join("\n")
ensure
  file.close
end

puts "\n"