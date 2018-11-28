# -*- encoding : ascii-8bit -*-

require 'web3/hpb/abi/type'
require 'web3/hpb/abi/constant'
require 'web3/hpb/abi/exceptions'
require 'web3/hpb/abi/utils'

module Web3::Hpb::Abi
  ##
  # abi的解码和编码
  # Contract ABI encoding and decoding.
  #
  module AbiCoder
    extend self

    include Constant
    class EncodingError < StandardError; end
    class DecodingError < StandardError; end
    class ValueOutOfBounds < ValueError; end

    ##
    # 使用head/tail机制编码多个参数
    # Encodes multiple arguments using the head/tail mechanism.
    #
    def encode_abi(types, args)
      parsed_types = types.map{ |t| Type.parse(t) }
      head_size = (0...args.size)
        .map{ |i| parsed_types[i].size || 32 }
        .reduce(0, &:+)

      head, tail = '', ''
      args.each_with_index do |arg, i|
        if parsed_types[i].dynamic?
          head += encode_type(Type.size_type, head_size, tail.size)
          tail += encode_type(parsed_types[i], arg)
        else
          head += encode_type(parsed_types[i], arg)
        end
      end

      "#{head}#{tail}"
    end

    alias :encode :encode_abi

    ##
    # Encodes a single value (static or dynamic).
    #
    # @param type [HPB::ABI::Type] value type
    # @param arg [Object] value
    #
    # @return [String] encoded bytes
    #

    def encode_type(type_arg)

      if %w(string bytes).include?(type.base) && type.sub.empty?
        encode_primitive_type(type, arg)
      elsif type.dynamic?

        raise ArgumentRrror, "arg must be an array" unless arg.instance_of?(Array)

        head, tail = '', ''
        if type.dims.last == 0
          head += encode_type(Type.size_type, arg.size)
        else
          raise ArgumentError, "Wrong array size: found #{arg.size}, expecting #{type.dims.last}" unless arg.size == type.dims.last
        end

        sub_type = type.subtype
        sub_size = type.subtype.size

        arg.size.times do |i|
          if sub_size.nil?
            head += encode_type(Type.size_type, 32*arg.size + tail.size)
            tail += encode_type(sub_type, arg[i])
          else
            head += encode_type(sub_type, arg[i])
          end
        end

        "#{head}#{tail}"
      else # static type
        if type.dims.empty?
          encode_primitive_type(type, arg)
        else
          arg.map { |x| encode_type(type.subtype, x) }.join
        end
      end

    end

    def encode_primitive_type(type, arg)
      case type.base
      when 'uint'
        begin
          real_size = type.sub.to_i
          i = get_unit(arg)

          raise ValueOutOfBounds, arg unless i >= 0 && i < 2**real_size
          utils.zpad_int(i)
        rescue EncodeingError
          raise ValueOutOfBounds, arg
        end
      when 'bool'
        raise ArgumentError, "arg is not bool: #{arg}" unless arg.instance_of?(TrueClass) || arg.instance_of?(FalseClass)
        Utils.zpad_int(arg ? 1 : 0)
      when 'int'
        begin
          real_size = type.sub.to_i
          i = get_int arg

          raise ValueOutOfBounds, arg unless i >= -2**(real_size-1) && i < 2**(real_size-1)
          Utils.zpad_int(i % 2**type.sub.to_i)
        rescue
          raise ValueOutOfBounds, arg
        end
      when 'ufixed'
        high, low = type.sub.split('x').map(&:to_i)

        raise ValueOutOfBounds, arg unless arg >= 0 && arg < 2**high
        Utils.zpad_int((arg * 2**low).to_i)
      when 'fixed'
        high, low = type.sub.split('x').map(&:to_i)

        raise ValueOutOfBounds, arg unless arg >= -2**(high - 1) && arg < 2**(high - 1)

        i = (arg * 2**low).to_i
        Utils.zpad_int(i % 2**(high+low))
      when 'string'
        if arg.encoding.name == 'UTF-8'
          arg = arg.b
        else
          begin
            arg.unpack('U*')
          rescue ArgumentError
            raise ValueError, "string must be UTF-8 encoded"
          end
        end

        if type.sub.empty? # variable length type
          raise ValueOutOfBounds, "Integer invalid or out of range: #{arg.size}" if arg.size >= TT256
          size = Utils.zpad_int(arg.size)
          value = Utils.rpad(arg, BYTE_ZERO, Utils.ceil32(arg.size))
          "#{size}#{value}"
        else # fixed length type
          sub = type.sub.to_i
          raise ValueOutOfBounds, "invalid string length #{sub}" if arg.size > sub
          raise ValueOutOfBounds, "invalid string length #{sub}" if sub < 0 || sub > 32
          Utils.rpad(arg, BYTE_ZERO, 32)
        end
      when 'bytes'
        raise EncodingError, "Expecting string: #{arg}" unless arg.instance_of?(String)
        arg = arg.b

        if type.sub.empty? # variable length type
          raise ValueOutOfBounds, "Integer invalid or out of range: #{arg.size}" if arg.size >= TT256
          size = Utils.zpad_int(arg.size)
          value = Utils.rpad(arg, BYTE_ZERO, Utils.ceil32(arg.size))
          "#{size}#{value}"
        else # fixed length type
          sub = type.sub.to_i
          raise ValueOutOfBounds, "invalid bytes length #{sub}" if arg.size > sub
          raise ValueOutOfBounds, "invalid bytes length #{sub}" if sub < 0 || sub > 32
          Utils.rpad(arg, BYTE_ZERO, 32)
        end
      when 'hash'
        size = type.sub.to_i
        raise EncodingError, "too long: #{arg}" unless size > 0 && size <= 32

        if arg.is_a?(Integer)
          Utils.zpad_int(arg)
        elsif arg.size == size
          Utils.zpad(arg, 32)
        elsif arg.size == size * 2
          Utils.zpad_hex(arg)
        else
          raise EncodingError, "Could not parse hash: #{arg}"
        end
      when 'address'
        if arg.is_a?(Integer)
          Utils.zpad_int(arg)
        elsif arg.size == 20
          Utils.zpad(arg, 32)
        elsif arg.size == 40
          Utils.zpad_hex(arg)
        elsif arg.size == 42 && arg[0,2] == '0x'
          Utils.zpad_hex(arg[2..-1])
        else
          raise EncodingError, "Could not parse address: #{arg}"
        end
      else
        raise EncodingError, "Unhandled type: #{type.base} #{type.sub}"
      end
    end

  end
end













