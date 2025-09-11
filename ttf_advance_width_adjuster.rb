#!/usr/bin/env ruby
# TTF Advance Width Adjuster
# 사용법: ruby ttf_adjuster.rb input.ttf output.ttf 0.9

class TTFAdvanceWidthAdjuster
  def initialize(input_file, output_file, scale_factor)
    @input_file = input_file
    @output_file = output_file
    @scale_factor = scale_factor
    @tables = {}
    @table_directory = []
  end

  def process
    puts "TTF 파일 처리 시작: #{@input_file}"
    puts "조절 비율: #{(@scale_factor * 100).round(1)}%"
    
    File.open(@input_file, 'rb') do |file|
      read_ttf_header(file)
      read_table_directory(file)
      read_all_tables(file)
      
      adjust_advance_widths
      
      write_output_file
    end
    
    puts "완료! 새 파일 저장: #{@output_file}"
  end

  private

  def read_ttf_header(file)
    @sfnt_version = file.read(4)
    @num_tables = read_uint16(file)
    @search_range = read_uint16(file)
    @entry_selector = read_uint16(file)
    @range_shift = read_uint16(file)
    
    puts "테이블 수: #{@num_tables}"
  end

  def read_table_directory(file)
    @num_tables.times do
      tag = file.read(4)
      checksum = read_uint32(file)
      offset = read_uint32(file)
      length = read_uint32(file)
      
      @table_directory << {
        tag: tag,
        checksum: checksum,
        offset: offset,
        length: length
      }
    end
    
    puts "발견된 테이블들: #{@table_directory.map { |t| t[:tag] }.join(', ')}"
  end

  def read_all_tables(file)
    @table_directory.each do |table_info|
      file.seek(table_info[:offset])
      data = file.read(table_info[:length])
      @tables[table_info[:tag]] = {
        data: data,
        info: table_info
      }
    end
  end

  def adjust_advance_widths
    unless @tables['hmtx'] && @tables['hhea']
      puts "경고: hmtx 또는 hhea 테이블을 찾을 수 없습니다."
      return
    end

    # hhea 테이블에서 numberOfHMetrics 읽기 (오프셋 34)
    hhea_data = @tables['hhea'][:data]
    num_h_metrics = hhea_data[34, 2].unpack('n')[0]
    
    puts "조정할 glyph 수: #{num_h_metrics}"

    # hmtx 테이블 데이터 가져오기
    old_hmtx_data = @tables['hmtx'][:data]
    new_hmtx_data = String.new('', encoding: 'ASCII-8BIT')

    adjusted_count = 0
    
    # 각 glyph의 advance width 조정
    num_h_metrics.times do |i|
      offset = i * 4
      
      # 현재 advance width와 lsb 읽기
      advance_width = old_hmtx_data[offset, 2].unpack('n')[0]
      lsb = old_hmtx_data[offset + 2, 2].unpack('n')[0]
      
      # advance width를 스케일 팩터로 조정
      new_advance_width = (advance_width * @scale_factor).round
      new_advance_width = [new_advance_width, 1].max # 최소값 1 보장
      
      if new_advance_width != advance_width
        adjusted_count += 1
      end
      
      # 새 데이터에 추가
      new_hmtx_data += [new_advance_width].pack('n')
      new_hmtx_data += [lsb].pack('n')
    end
    
    # 나머지 LSB 값들 복사 (advance width가 마지막과 동일한 글리프들)
    remaining_offset = num_h_metrics * 4
    if remaining_offset < old_hmtx_data.length
      remaining_data = old_hmtx_data[remaining_offset..-1]
      new_hmtx_data += remaining_data
    end
    
    # 테이블 업데이트
    @tables['hmtx'][:data] = new_hmtx_data
    @tables['hmtx'][:info][:length] = new_hmtx_data.length
    
    puts "#{adjusted_count}개 글리프의 advance width가 조정되었습니다."
  end

  def write_output_file
    File.open(@output_file, 'wb') do |file|
      # TTF 헤더 쓰기
      file.write(@sfnt_version)
      write_uint16(file, @num_tables)
      write_uint16(file, @search_range)
      write_uint16(file, @entry_selector)
      write_uint16(file, @range_shift)
      
      # 테이블 디렉토리 오프셋 계산
      current_offset = 12 + (@num_tables * 16) # 헤더 + 디렉토리 크기
      current_offset = (current_offset + 3) & ~3 # 4바이트 정렬
      
      # 체크섬을 위한 위치 저장
      checksum_positions = []
      
      # 테이블 디렉토리 쓰기
      @table_directory.each_with_index do |table_info, index|
        file.write(table_info[:tag])
        
        checksum_pos = file.pos
        checksum_positions << checksum_pos
        write_uint32(file, 0) # checksum - 나중에 계산
        
        write_uint32(file, current_offset)
        
        table_data = @tables[table_info[:tag]][:data]
        write_uint32(file, table_data.length)
        
        # 다음 테이블 오프셋 계산
        current_offset += table_data.length
        current_offset = (current_offset + 3) & ~3 # 4바이트 정렬
      end
      
      # 테이블 데이터 쓰기 및 체크섬 계산
      @table_directory.each_with_index do |table_info, index|
        # 4바이트 정렬
        while file.pos % 4 != 0
          file.write("\0")
        end
        
        data_start = file.pos
        table_data = @tables[table_info[:tag]][:data]
        file.write(table_data)
        
        # 패딩 추가
        while file.pos % 4 != 0
          file.write("\0")
        end
        
        # 체크섬 계산 (데이터를 직접 사용)
        table_data = @tables[table_info[:tag]][:data]
        # 4바이트 정렬을 위한 패딩 추가
        padded_length = ((table_data.length + 3) / 4) * 4
        padded_data = table_data.ljust(padded_length, "\0")
        checksum = calculate_checksum(padded_data)
        
        # 체크섬 업데이트
        current_pos = file.pos
        file.seek(checksum_positions[index])
        write_uint32(file, checksum)
        file.seek(current_pos)
      end
    end
  end

  # 유틸리티 메서드들
  def read_uint16(file)
    file.read(2).unpack('n')[0]
  end

  def read_uint32(file)
    file.read(4).unpack('N')[0]
  end

  def write_uint16(file, value)
    file.write([value].pack('n'))
  end

  def write_uint32(file, value)
    file.write([value].pack('N'))
  end

  def calculate_checksum(data)
    # 4바이트씩 더해서 체크섬 계산
    sum = 0
    (0...data.length).step(4) do |i|
      chunk = data[i, 4].ljust(4, "\0")
      sum += chunk.unpack('N')[0]
      sum &= 0xFFFFFFFF
    end
    sum
  end
end

# 메인 실행 부분
if ARGV.length != 3
  puts "사용법: ruby ttf_adjuster.rb input.ttf output.ttf scale_factor"
  puts "예시: ruby ttf_adjuster.rb font.ttf font_narrow.ttf 0.9"
  puts ""
  puts "scale_factor 예시:"
  puts "  0.9  - 10% 줄임 (90% 크기)"
  puts "  0.8  - 20% 줄임 (80% 크기)" 
  puts "  0.85 - 15% 줄임 (85% 크기)"
  exit 1
end

input_file = ARGV[0]
output_file = ARGV[1]
scale_factor = ARGV[2].to_f

unless File.exist?(input_file)
  puts "오류: 입력 파일을 찾을 수 없습니다: #{input_file}"
  exit 1
end

if scale_factor <= 0 || scale_factor > 4
  puts "오류: scale_factor는 0과 4 사이의 값이어야 합니다."
  exit 1
end

begin
  adjuster = TTFAdvanceWidthAdjuster.new(input_file, output_file, scale_factor)
  adjuster.process
rescue => e
  puts "오류 발생: #{e.message}"
  puts e.backtrace if ENV['DEBUG']
  exit 1
end