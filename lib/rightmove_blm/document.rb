# frozen_string_literal: true

module RightmoveBLM
  # A BLM document including its header, definition, and data content.
  class Document # rubocop:disable Metrics/ClassLength
    BLM_FILE_SECTIONS = %w[HEADER DEFINITION DATA END].freeze

    def self.from_array_of_hashes(array, international: false, eor: '~', eof: '^')
      date = Time.now.utc.strftime('%d-%b-%Y %H:%M').upcase
      version = international ? '3i' : '3'
      header = { version: version, eof: eof, eor: eor, 'property count': array.size.to_s, 'generated date': date }
      new(header: header, definition: array.first.keys.map(&:to_sym), data: array)
    end

    def initialize(source: nil, header: nil, definition: nil, data: nil, name: nil)
      @source = source || data
      @header = header
      @definition = definition
      @name = name
      initialize_with_data(data) unless data.nil?
      verify_source_file_structure(source) unless source.nil?
    end

    def inspect(safe: false, error: nil)
      name = @name.nil? ? nil : %( document="#{@name}")
      error_string = error.nil? ? nil : %( error="#{error}")
      basic = %(<##{self.class.name}#{name}#{error_string}>)
      return basic if safe

      "<##{self.class.name}#{name}#{error_string} version=#{version} " \
        "rows=#{rows.size} valid=#{valid?} errors=#{errors.size}>"
    end

    def to_s
      inspect
    end

    def to_blm
      [
        header_string,
        definition_string,
        data_string
      ].join("\n")
    end

    def header
      @header ||= contents(:header).each_line.map do |line|
        next nil if line.empty?

        key, _, value = line.partition(':')
        next nil if value.nil?

        [normalized_key(key), value.tr("'", '').strip]
      end.compact.to_h
    end

    def definition
      @definition ||= contents(:definition).split(eor).first.split(eof).map do |field|
        next nil if field.empty?

        field.downcase.strip
      end.compact
    end

    def rows
      data
    end

    def errors
      @errors ||= data.reject(&:valid?).flat_map(&:errors)
    end

    def valid?
      errors.empty?
    end

    def version
      header[:version]
    end

    def international?
      %w[H1 3I 3i].include?(version)
    end

    private

    def initialize_with_data(data)
      @data = data.each_with_index.map { |hash, index| Row.from_attributes(hash, index: index) }
    end

    def data
      @data ||= contents.split(header[:eor]).each_with_index.map do |line, index|
        Row.new(index: index, data: line, separator: header[:eof], definition: definition)
      end
    end

    def contents(section = :data)
      marker = "##{section.to_s.upcase}#"
      start = verify_marker_presence(:start, @source.index(marker)) + marker.size
      finish = verify_marker_presence(:end, @source.index('#END#', start)) - 1
      @source[start..finish].strip
    rescue Encoding::CompatibilityError => e
      raise_parser_error 'Unable to parse document due to encoding error.', e
    end

    def normalized_key(key)
      key.strip.downcase.to_sym
    rescue ArgumentError => e
      raise_parser_error "Unable to parse document. Error found in header for key `#{key}`", e
    end

    # INFO : for reverse compatibility. can remove this method and it's calls within this update.
    # verify_file_structure should cover all cases of this method calls
    def verify_marker_presence(type, val)
      return val unless val.nil?

      raise_parser_error "Unable to parse document: could not detect #{type} marker."
    end

    def verify_source_file_structure(source)
      BLM_FILE_SECTIONS.each do |section|
        next if source.index(section)

        raise_parser_error "Unable to process document with this structure: could not detect #{section} section."
      end
    end

    def generated_date
      header[:'generated date'] || Time.now.utc.strftime('%d-%b-%Y %H:%M').upcase
    end

    def header_string
      ['#HEADER#', "VERSION : #{header[:version]}", "EOF : '#{eof}'", "EOR : '#{eor}'",
       "Property Count : #{data.size}", "Generated Date : #{generated_date}", '']
    end

    def definition_string
      ['#DEFINITION#', "#{definition.join(eof)}#{eof}#{eor}", '']
    end

    def data_string
      ['#DATA#', *data.map { |row| "#{row.attributes.values.join(eof)}#{eor}" }, '#END#']
    end

    def raise_parser_error(message, cause = nil)
      raise ParserError, "#{inspect(safe: true)}: #{message} #{cause}"
    end

    def eor
      header[:eor]
    end

    def eof
      header[:eof]
    end
  end
end