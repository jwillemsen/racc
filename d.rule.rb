
  class BuildInterface

    def initialize( racc )
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable

      @precs = []

      @end_rule = false
      @end_conv = false
      @end_prec = false
    end

    
    def get_token( val )
      @tokentable.get( val )
    end
    
    def register_rule( simbol, rulearr, tempprec, actstr )
      puts "register: add: #{simbol} -> #{rulearr.join(' ')}" if @d_rule

      if @end_rule then
        raise ParseError, "'rule' block is defined twice"
      end

      if simbol then
        @pre = simbol
      else
        simbol = @pre
      end
      unless actstr then actstr = '' end

      @ruletable.register( simbol, rulearr, tempprec, actstr )
    end

    def end_register_rule
      @end_rule = true
    end


    def register_prec( atr, toks )
      puts "register: atr=#{atr.id2name}, toks=#{toks.join(' ')}" if @d_prec

      if @end_prec then
        raise ParseError, "'prec' block is defined twice"
      end

      toks.push atr
      @precs.push toks
    end

    def end_register_prec( rev )
      @end_prec = true

      top = @precs.size - 1
      @precs.each_with_index do |toks, idx|
        atr = toks.pop

        toks.each do |tok|
          tok.assoc = atr
          if rev then
            tok.prec = top - idx
          else
            tok.prec = idx
          end
        end
      end
    end


    def register_conv( tok, str )
      if @end_conv then
        raise ParseError, "'token' block is defined twice"
      end

      tok.conv = str
    end

    def end_register_conv
      @end_conv = true
    end

  end
    

  class RuleTable

    def initialize( rac )
      @racc = rac
      @tokentable = rac.tokentable

      @d_token = rac.d_token
      @d_rule  = rac.d_rule
      @d_state = rac.d_state

      @rules    = []
      @finished = false
      @hashval  = 4
    end


    def register( simbol, rulearr, tempprec, actstr )
      rule = Rule.new(
        simbol, rulearr, actstr,
        @rules.size + 1,         # ID
        @hashval,                # hash value
        tempprec                 # prec
      )
      @rules.push rule

      @hashval += rulearr.size + 2
    end
   
    
    attr :start

    def do_initialize( start = nil )

      ### add dummy rule

      @start = start || @rules[0].simbol

      temp = Rule.new( @tokentable.dummy,
             [ @start, @tokentable.anchor, @tokentable.anchor ], '',
             0, 0, nil )
           # id hash prec
      @rules.unshift temp
      @rules.freeze


      ### cache

      @rules.each do |rule|
        rule.simbol.rules.push rule.ptrs(0)
      end

      @tokentable.each do |tok|
        tok.term = (tok.rules.size == 0)
      end

      @rules.each do |rule|
        temp = nil

        rule.each_ptr do |ptr|
          tok = ptr.unref
          tok.locate.push ptr
          temp = tok if tok.term
        end

        rule.prec = temp if rule.prec.nil?
      end
    end


    def []( x )
      @rules[x]
    end

    def each_rule( &block )
      @rules.each( &block )
    end
    alias each each_rule

    def each_index( &block )
      @rules.each_index( &block )
    end

    def each_with_index( &block )
      @rules.each_with_index( &block )
    end

    def size
      @rules.size
    end

    def to_s
      "<Racc::RuleTable>"
    end


    def closure( ptrs )
      ptrs = orig_ptrs.uniq
      puts "closure: start: ptrs #{ptrs.join(' ')}" if @d_state

      temp = {}
      ptrs.each do |ptr|
        temp.store( ptr, true )

        tok = ptr.unref
        ptr.reduce? or tok.term or temp.update( tok.expand )
      end
      ret = temp.keys
      ret.sort!{|a,b| a.hash <=> b.hash }

      puts "closure: ret #{ret.join(' ')}" if @d_state
      return ret
    end

  end   # class RuleTable



  class Rule

    def initialize( tok, rlarr, actstr, rid, hval, tprec )
      @simbol  = tok
      @rulearr = rlarr
      @action  = actstr
      @ruleid  = rid
      @hash    = hval
      @prec    = tprec

      @ptrs = []
      rlarr.each_index do |idx|
        @ptrs[ idx ] = RulePointer.new( self, idx, rlarr[idx] )
      end

      # reduce pos
      s = rlarr.size
      @ptrs[ s ] = RulePointer.new( self, s, nil )
    end


    attr :action
    attr :simbol
    attr :ruleid
    attr :hash
    attr :prec, true

    def ==( other )
      Rule === other and @ruleid == other.ruleid
    end

    def accept?()
      if tok = @rulearr[-1] then
        tok.anchor?
      else
        false
      end
    end

    def []( idx )
      @rulearr[idx]
    end

    def size
      @rulearr.size
    end

    def to_s
      "<Rule:ID #{@ruleid}>"
    end

    def ptrs( idx )
      @ptrs[idx]
    end

    def pointers
      @ptrs.dup
    end

    def toks( idx )
      @rulearr[idx]
    end

    def tokens
      @rulearr.dup
    end

    def each_token( &block )
      @rulearr.each( &block )
    end
    alias each each_token

    def each_with_index( &block )
      @rulearr.each_with_index( &block )
    end

    def each_ptr( &block )
      pmax = @ptrs.size - 1
      i = 0
      while i < pmax do
        yield @ptrs[i]
        i += 1
      end
    end

  end   # class Rule



  class RulePointer

    attr :rule
    attr :ruleid
    attr :index
    attr :unref
    attr :data
    attr :hash


    def initialize( rl, idx, tok )
      @rule   = rl
      @ruleid = rl.ruleid
      @index  = idx
      @unref  = tok

      @hash   = @rule.hash + @index
      @reduce = tok.nil?
    end


    def to_s
      sprintf( '(%d,%d %s)',
               @rule.ruleid, @index, reduce? ? '#' : unref.to_s )
    end
    alias inspect to_s

    #def inspect
    #  bug! 'ptr.inspect call'
    #end

    def eql?( ot )
      @hash == ot.hash
    end
    alias == eql?

    def reduce?
      @unref.nil?
    end

    def head?
      @index == 0
    end

    def increment
      unless ret = @rule.ptrs( @index + 1 ) then
        ptr_bug!
      end
      return ret
    end

    def decrement
      unless ret = @rule.ptrs( @index - 1 ) then
        ptr_bug!
      end
      return ret
    end

    private
    
    def ptr_bug!
      bug! "pointer not exist: self: #{to_s}"
    end

  end   # class RulePointer



  class TokenTable

    include Enumerable

    def initialize( racc )
      @nextid = 2
      @chk = {}
      @tokens = []
      
      @default = get( :$default, Token::Default )
      @dummy   = get( :$start,   Token::Dummy )
      @anchor  = get( :$end,     Token::Anchor )
    end

attr :tokens
    def get( val, tid = nil )
      unless ret = @chk[ val ] then
        unless tid then
          tid = @tokens.size
          tid = 2 if tid < 2
        end
        ret = Token.new( val, tid )
        @chk[ val ] = ret
        @tokens[tid] = ret if tid >= 0
      end

      ret
    end

    def each( &block )
      @tokens.each &block
      block.call @anchor
    end

    attr :dummy
    attr :anchor
    attr :default

  end


  class Token

    Anchor  = -1
    Default = 0
    Dummy   = 1

    def initialize( tok, tid )
if Token === tok then
  bug! 'Token for Token.new'
end
      @value = tok
      @tokenid = tid

      @dummy   = (tid == Dummy)
      @anchor  = (tid == Anchor)
      @defualt = (tid == Default)
      @hash    = @value.hash

      @rules  = []
      @locate = []
      @term   = nil
      @first  = nil
      @conv   = nil
      @nullp  = nil
      @bfrom  = nil
    end

    attr     :value
    attr     :tokenid
    attr     :rules
    attr     :locate
    attr     :term,                true
    attr     :nullp,               true
    attr     :assoc,               true
    attr     :prec,                true
    property :conv,  String, true, true

    alias terminal? term
    alias null?     nullp

    attr :dummy
    attr :anchor
    attr :hash

    alias dummy?  dummy
    alias anchor? anchor


    def to_s   # for system internal
      case @value
      when Integer then @value.id2name
      when String  then @value.inspect
      else
        bug! "wrong token value: #{@value}(#{@value.type})"
      end
    end
    alias inspect to_s

    def uneval   # for output
      if    @conv              then @conv
      elsif anchor?            then 'false'
      elsif Integer === @value then ':' + @value.id2name
      elsif String === @value  then @value.inspect
      else
        bug! "wrong token value: #{@value}(#{@value.type})"
      end
    end


    def first
      puts "get_first: start: token=#{self.to_s}" if @d_token

      return @first if @first
      @first = {}

      ret = {}
      @nullp = false

      if @term then
        bug! '"first" called for terminal'
      else
        tmp = {}
        @rules.each do |ptr|
          if ptr.reduce? then
            # reduce at index 0 --> null
            @nullp = true
          else
            tmp[ ptr.unref ] = true
          end
        end

        tmp.each_key do |tok|
          ret.update tok.first unless tok.terminal?
        end
      end

      @first = ret
      puts "get_first: for=#{token}; ret=#{ret.keys.join(' ')}" if @d_token

      return ret
    end


    def expand
      puts "expand: start: tok=#{self}" if @d_state

      return @bfrom if @bfrom
      @bfrom = 1                           #####

      ret = {}
      tmp = {}
      @rules.each do |ptr|
        ret.store( ptr, true )
        tok = ptr.unref
        if not ptr.reduce? and not tok.terminal? then
          tmp[ tok ] = true
        end
      end
      tmp.each_key do |tok|
        if (h = tok.expand) != 1 then      #####
          ret.update h
        end
      end

      @bfrom = ret
      puts "expand: ret #{ret.keys.join(' ')}" if @d_state

      return ret
    end

  end   # Token

