class TeamCityFormatter < Cucumber::Ast::Visitor
  
  def initialize(step_mother, io, options, delim='|')
    super(step_mother)
    @io = io
    @options = options
    @current_feature_element = nil
    @current_feature = nil
    @current_step=nil

    @failed_scenarios = {}
    @test_output=[]

    # we have to store global state to get
    # our final exit message. Oh, for the want of a destructor.
    $_TEAMCITY_EXIT_MESSAGE=nil
    at_exit do
      puts $_TEAMCITY_EXIT_MESSAGE unless $_TEAMCITY_EXIT_MESSAGE.nil?
    end
  end

  # = AST Visitor hooks
  
  # Hook for new feature.
  # Because cucumber does not provide begin and end hooks,
  # we store the feature name and issue a Finished when it changes
  def visit_feature_name(name)
    name=name.split("\n").first
    @current_feature=name if @current_feature.nil?
    if name != @current_feature
      testsuite_finish(@current_feature)
      @current_feature=name
    end
    testsuite_start(@current_feature)
  end

  def visit_exception(exception, status)
    test_failure(@current_step,format_exception(exception)) if status == :failed
  end

  # put each step into the messages buffer. Because of the way teamcity formats
  # output, we want to output all our messages at the same time
  def visit_step_name(keyword, step_match, status, source_indent, background)
    line=format_step(keyword, step_match, status)
    @current_step=line
    if status != :passed
      test_message(line, 'WARNING')
    else
      test_message(line)
    end
    super
    # this has to be (re-)defined here, since cucumber does
    # not provide hooks at the end of a test(suite), and we want
    # to let teamcity know we've finished
    $_TEAMCITY_EXIT_MESSAGE=%Q(
#{test_messages(:purge => false)}
##teamcity[testFinished name='#{@current_feature_element}']
##teamcity[testSuiteFinished name='#{@current_feature}']
    )
  end

  def visit_scenario_name(keyword, name, file_colon_line, source_indent)
    visit_feature_element_name(keyword, name, file_colon_line, source_indent)
  end

  # Because cucumber does not provide begin and end hooks,
  # we store the scenario name and issue a Finished when it changes
  def visit_feature_element_name(keyword, name, file_colon_line, source_indent)
    line = %Q("#{name}")
    if @options[:source]
      line = line + ' @ ' + file_colon_line
    end
    @current_feature_element=line if @current_feature_element.nil?
    if line != @current_feature_element
      test_finish(@current_feature_element)
      @current_feature_element=line
    end
    test_start(line)

  end
 
  #
  # = Logging Methods
  #
  
  # log the beginning of a scenario
  def testsuite_start(msg, io=@io)
    msg=teamcity_escape(msg)
    io.puts "##teamcity[testSuiteStarted #{timestamp} name='#{msg}']"
    io.flush
  end

  # log the end of a feature
  def testsuite_finish(msg, io=@io)
    msg=teamcity_escape(msg)
    io.puts "##teamcity[testSuiteFinished #{timestamp} name='#{msg}']"
    io.flush
  end

  # log the start of a scenario
  def test_start(msg)
    msg=teamcity_escape(msg)
    @io.puts "##teamcity[testStarted #{timestamp} name='#{msg}' captureStandardOutput='true']"
    @io.flush
  end

  # log the end of a scenario
  def test_finish(msg)
    msg=teamcity_escape(msg)
    @io.puts test_messages(:purge => true)
    @io.puts "##teamcity[testFinished #{timestamp} name='#{msg}']"
    @io.flush
  end

  # add a message from step output to buffer
  # right now, type is ignored, since we have no reasonably
  # attractive way to add that to teamcity
  def test_message(msg, type = 'NORMAL')
    @test_output.push(teamcity_escape(msg))
  end

  # return a string formatted for use by teamcity which includes all messages
  # if :purge is true (the default), then the buffer is also emptied
  def test_messages(opt={})
    purge = opt[:purge]||true
    ret=''
    return ret if @test_output.empty?
    ret=@test_output.join('|n') #teamcity escaped newline
    @test_output=[] if purge
    return "##teamcity[message text='|n#{ret}|n']"
  end
  
  # Log a test failure
  def test_failure(msg, details='')
    # teamcity wants on a single failure per test,
    # but since tests are scenarios, not steps,
    # we need to log only once per scenario
    return unless @failed_scenarios[@current_feature_element].nil?
    msg=teamcity_escape(msg)
    details=teamcity_escape(details)
    name=teamcity_escape(@current_feature_element)
    @failed_scenarios[@current_feature_element]="#{msg} #{details}"
    @io.puts "##teamcity[testFailed #{timestamp} name='#{name}' message='#{msg}' details='#{details}']"
    @io.flush
  end
  
  private
  
  # = Formating Methods
  
  def format_step(keyword, step_match, status)
    %q{%s %10s %s %-90s @ %s} % [timestamp_short, status, keyword,
                                     step_match.format_args(lambda{|param| param}),
                                     step_match.file_colon_line]
  end

  def format_exception(exception)
    (["#{exception.message} (#{exception.class})"] + exception.backtrace).join("\n")
  end

  # make necessary escapes for teamcity
  def teamcity_escape(str)
    str = str.to_s.strip
    str.gsub!('|', '||')
    str.gsub!("\n", '|n')
    str.gsub!("\r", '|r')
    str.gsub!("'", "|'")
    str.gsub!(']', '|]')
    return str
  end

  def timestamp_short
    t = Time.now
    ts=t.strftime('%H:%M:%S.%%0.3d') % (t.usec/1000)
  end

  def timestamp
    t = Time.now
    ts=t.strftime('%Y-%m-%dT%H:%M:%S.%%0.3d') % (t.usec/1000)
    " timestamp='#{ts}' "
  end

end