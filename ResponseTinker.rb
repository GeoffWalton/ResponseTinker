require 'java'
java_import 'burp.IExtensionHelpers'
java_import 'burp.IBurpExtender'
java_import 'javax.swing.JOptionPane'
java_import 'burp.ITab'
java_import 'javax.swing.JPanel'
java_import 'javax.swing.JScrollPane'
java_import 'java.awt.Dimension'
java_import 'java.awt.Rectangle'
java_import 'java.awt.event.ComponentListener'

class ThreadSafeObject
  instance_methods.each do |m|
    undef_method(m) unless m =~ /(^__|^nil\?$|^send$|^object_id$)/
  end

  def initialize(object, *args, &block)
    @object = object.send(:new, *args, &block)
    @sync = Mutex.new
  end

  def method_missing(m, *args, &blk)
    if @sync.owned?
      @object.send(m, *args, &blk)
    else
      @sync.synchronize do
        @object.send(m, *args, &blk)
      end
    end
  end
end

module BurpHelpers
  def self.included(base)
    base.send :include, InstanceMethods
    base.extend StaticMethods
  end

  module StaticMethods
    def extensionHelpers=(v)
      @helpers = v
    end

    def extensionHelpers
      @helpers
    end

    def extenderCallbacks=(v)
      @callbacks = v
      @helpers = @callbacks.getHelpers
    end

    def extenderCallbacks
      @callbacks
    end
  end

  module InstanceMethods
    def method_missing(symbol, *args, &blk)
      self.class.extensionHelpers.send symbol, *args, &blk
    end

    def puts_err(str)
      self.class.extenderCallbacks.printError  str
    end

    def puts(str)
      self.class.extenderCallbacks.printOutput str
    end
  end
end

class AbstractBrupExtensionUI < JScrollPane
  include ITab
  include ComponentListener

  attr_reader :extensionName

  def initialize(name)
    @extensionName = name
    @panel = JPanel.new
    @panel.setLayout nil
    super(@panel)
    addComponentListener self
  end

  def add(component)
    bounds = component.getBounds
    updateSize(bounds.getX + bounds.getWidth, bounds.getY + bounds.getHeight)
    @panel.add component
  end

  alias_method :getTabCaption, :extensionName

  def getUiComponent
    self
  end

  def componentHidden(componentEvent); end

  def componentMoved(componentEvent); end

  def componentResized(componentEvent); end

  def componentShown(componentEvent);end

  def errorMessage(text)
    JOptionPane.showMessageDialog(self, text, 'Error', 0)
  end

  def message(text)
    JOptionPane.showMessageDialog(self, text)
  end

  private
  #Don't set the size smaller than existing widget positions
  def updateSize(x,y)
    x = (@panel.getWidth() > x) ? @panel.getWidth : x
    y = (@panel.getHeight() > y) ? @panel.getHeight : y
    @panel.setPreferredSize(Dimension.new(x,y))
  end

end

java_import('java.awt.Insets')
class AbstractBurpUIElement
  def initialize(parent, obj, positionX, positionY, width, height)
    @swingElement =obj
    setPosition parent, positionX, positionY, width, height
    parent.add @swingElement
  end

  def method_missing(method, *args, &block)
    @swingElement.send(method, *args)
  end

  private
  def setPosition(parent, x,y,width,height)
    insets = parent.getInsets
    size = @swingElement.getPreferredSize()
    w = (width > size.width) ? width : size.width
    h = (height > size.height) ? height : size.height
    @swingElement.setBounds(x + insets.left, y + insets.top, w, h)
  end
end

java_import 'javax.swing.JLabel'
class BLabel < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, width, height, caption, align= :left)
    case align
    when :left
      a = 2
    when :right
      a = 4
    when :center
      a = 0
    else
      a = 2 #align left
    end
    super parent, JLabel.new(caption, a),positionX, positionY, width, height
  end
end

java_import 'javax.swing.JButton'
class BButton < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, width, height, caption, &onClick)
    super parent, JButton.new(caption), positionX, positionY, width, height
    @swingElement.add_action_listener onClick
  end
end

java_import 'javax.swing.JSeparator'
class BHorizSeparator < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, width)
    super parent, JSeparator.new(0), positionX, positionY, width, 1
  end
end

class BVertSeparator < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, height)
    super parent, JSeparator.new(1), positionX, positionY, 1, height
  end
end

java_import 'javax.swing.JCheckBox'
class BCheckBox < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, width, height, caption)
    super parent, JCheckBox.new(caption), positionX, positionY, width, height
  end
end

java_import 'javax.swing.JTextField'
class BTextField < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, width, height, caption)
    super parent, JTextField.new(caption), positionX, positionY, width, height
  end
end

java_import 'javax.swing.JList'
class BListBox < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, width, height, &evt)
    super parent, JList.new, positionX, positionY, width, height
    @swingElement.addListSelectionListener evt
  end
end

java_import 'javax.swing.JTextArea'
class BTextArea < AbstractBurpUIElement
  def initialize(parent, positionX, positionY, width, height)
    @textArea = JTextArea.new
    super parent, @textArea, positionX, positionY, width, height
    @textArea.setLineWrap(true)
  end
end

java_import 'burp.ITextEditor'
class BTextEditor < AbstractBurpUIElement
  def initialize(parent, callbacks, positionX, positionY, width, height)
    @textArea = callbacks.createTextEditor
    super parent, @textArea.getComponent, positionX, positionY, width, height
  end

  def setText(text)
    @textArea.setText text.bytes
  end

  def getText
    @textArea.getText.map {|b| b.chr}.join
  end

  def setEditable(bool)
    @textArea.setEditable bool
  end

  def getSelectedText
    @textArea.getSelectedText
  end

  def getSelectionBounds
    @textArea.getSelectionBounds
  end
end

#########################################################################################
#Begin Burp Extension
#########################################################################################
java_import 'burp.IProxyListener'
class ProxyServer
  include BurpHelpers
  include IProxyListener

  PROXY = 0x00000004

  def initialize()
    @servlets = ThreadSafeObject.new Array
    @requests = ThreadSafeObject.new Hash
  end

  def register!
    self.class.extenderCallbacks.registerProxyListener self
    puts 'Registered Proxy Listener'
  end

  def unregister!
    self.class.extenderCallbacks.removeProxyListener self
    puts 'Registered Proxy Listener'
  end

  def add_servlet(text, path)
    remove_servlet path #Remove it if it already exists
    klass = eval "Class.new(ProxyServer::Servlet) do\n#{text}\nend"
    klass.path = path
    klass.text = text
    klass.extenderCallbacks = self.class.extenderCallbacks
    @servlets << klass
  end

  def remove_servlet(path)
    l = @servlets.length
    @servlets.delete_if { |c| c.path == path }
    @servlets.length < l
  end

  def get_servlet(path)
    @servlets.select {|c| (c.path.is_a?(Regexp) ? c.path.inspect : c.path) == path.to_s }[0]
  end

  def routes
    @servlets.each do |s|
      yield (s.path.is_a?(Regexp) ? s.path.inspect : s.path)
    end
  end

  def route(url)
    paths = Array.new
    paths << url.to_s
    #Some alternative representations without the port
    if url.respond_to? :protocol #then it is a url object not a string
      paths << "https://#{url.host}#{url.file}" if ((url.protocol == 'https') and (url.port == 443))
      paths << "http://#{url.host}#{url.file}" if ((url.protocol == 'http') and (url.port == 80))
    end
    m = @servlets.select do |klass|
      if klass.path.is_a? Regexp
        ((paths.select {|p| klass.path =~ p }.count) > 0)
      else #try and match a string
        paths.include? klass.path
      end
    end
    m[0]
  end

  def processProxyMessage(messageIsRequest, message)
    if messageIsRequest
      @requests[message.getMessageReference] = message.getMessageInfo
    else #modify the response
      req = @requests.delete message.getMessageReference
      unless req
        puts_err 'Response with no matching request encountered'
      else
        rsp = message.getMessageInfo
        req_info = analyzeRequest req.getHttpService, req.getRequest
        servlet = route(req_info.getUrl)
        return unless servlet #Nothing to modify this request with
        servlet.new(req_info, req.getRequest, rsp).execute
      end
    end
  end

  class Servlet
    include BurpHelpers

    def self.path=(s)
      @path = s
      puts "New route for url #{(s.is_a?(Regexp) ? s.inspect : s)}"
    end

    def self.path
      @path
    end

    def self.text
      @text ||= ''
    end

    def self.text=(v)
      @text = v
    end

    def initialize(req_info, request, response)
      @response = response
      rsp_info = analyzeResponse(response.getResponse)
      @rsp = {}
      @rsp['body'] = bytesToString(response.getResponse[rsp_info.getBodyOffset..-1])
      @rsp['status'] = rsp_info.getStatusCode
      @rsp.default = Hash.new
      @rsp['headers'] = [] #response headers may be duplicate key 'set-cookie'
      @req = {}
      @req.default = Hash.new
      @req['method'] = req_info.getMethod
      @req['body'] = bytesToString(request[req_info.getBodyOffset()..-1])
      rsp_info.getHeaders.each {|line| a = line.split(': '); @rsp['headers'] << [a[0],a[1..-1].join] unless a[0].downcase == 'content-length'}
      req_info.getHeaders.each {|line| a = line.split(': '); @req['headers'][a[0]] = a[1..-1].join }
      req_info.getParameters.each do |p|
        if p.getType == 2
          @req['cookies'][p.getName] = p.getValue
        else
          @req['parameters'][p.getName] = p.getValue
        end
      end
    end

    def execute
      unless self.respond_to? "do_#{@req['method']}".to_sym
        return #pass the server response
      else
        puts "Handling response for #{@req['method']} #{self.class.path}"
        self.send "do_#{@req['method']}".to_sym, @req, @rsp
      end
      final_response = Array.new
      final_response << @rsp['headers'][0][0].sub(/[0-9]{3}/, @rsp['status'].to_s)
      final_response << "Content-Length: #{@rsp['body'].bytesize}"
      @rsp['headers'].delete_at 0
      @rsp['headers'].each {|h| final_response << h.join(': ') }
      final_response << '' #emtpy line
      final_response << @rsp['body']
      @response.setResponse stringToBytes final_response.join "\r\n"
    end
  end
end

class MainTab < AbstractBrupExtensionUI
  include BurpHelpers

  OFFTEXT = 'Master On/[Off]'
  ONTEXT = 'Master [On]/Off'

  def initialize(extension)
    super
    @proxy = ProxyServer.new
    buildUI
  end

  def componentResized(evt)
    onResize
      #puts [bounds.getX, bounds.getWidth, bounds.getY, bounds.getHeight].to_s
  end

  def buildUI
    @btnOnOff = BButton.new(self, 20, 20, 200, 30, OFFTEXT) {|e| onOffOnClick }
    @btnInsert = BButton.new(self, 1,1,1,1,'Insert') {|e| insertOnClick }
    @btnRemove = BButton.new(self, 1,1,1,1,'Remove') {|e| removeOnClick }
    BLabel.new(self, 20, 70, 20,30,'URL:')
    @hsep1 = BHorizSeparator.new self, 0, 55, 2
    @txtURL = BTextField.new(self, 25, 70, 100, 30, 'https://example.com/')
    @btnHelp = BButton.new(self, 220, 20, 200, 30, "Help") {|e| helpOnClick }
    @txtArea = BTextEditor.new( self, self.class.extenderCallbacks, 2, 2,2,2)
    @lstRoutes = BListBox.new(self, 0, 110,1,1) {|e| routesOnClick}
    onResize
    template
  end

  def onResize
    bounds = self.getBounds
    @hsep1.setBounds(0,55,bounds.getWidth,2)
    @txtURL.setBounds(50, 70, bounds.getWidth - 450, 30)
    @txtArea.setBounds(2, 110, bounds.getWidth - 400, bounds.getHeight - 110)
    @btnHelp.setBounds(bounds.getWidth - 220, 20, 200, 30)
    w = (bounds.getWidth - (bounds.getWidth - 390))/2
    @btnInsert.setBounds(bounds.getWidth - 393, 70, w, 30)
    @btnRemove.setBounds((bounds.getWidth - 393) + w, 70, w, 30)
    @lstRoutes.setBounds((bounds.getWidth - 393), 110, 2 * w, bounds.getHeight - 110)
  end

  def helpOnClick
    message (<<-HELP
Add URL handlers on the URL line (protocol://host/path/) trailing backslash likely needed, query string much match 
A leading / means the pattern is a regular expression (ruby) in the form /EXPR/opts it needs to match the full URL

Provide functions for whatever request methods you need to handle as do_METHOD, ie do_GET
Requests without a handler method will not be altered
The signature should be do_METHOD(request, response)

Some useful things about the request object (read only)
request['method'] returns the method as a string
request['cookies']['<cookie>'] returns the cookie value as a string
request['body'] returns the request body as a string
request['headers']['<header>'] returns the header value as string
request['parameters']['<p>'] parameter p as string

Some useful response object information (read write)
resposne['body'] the response body
resposne['headers'] and array of ['header','value'] pairs ie [[]]
response['status'] the code ie 200
HELP
)
  end

  def template
    @txtArea.setText(<<-'TEMPLATE'
def do_GET(req, rsp)
 rsp['status'] = 202
 rsp['body'] = "<!doctype html>\r\n<html><body>Hi there!</body></html>"
end
TEMPLATE
)
  end

  def onOffOnClick
    if @btnOnOff.getText.to_s == OFFTEXT
      @proxy.register!
      @btnOnOff.setText(ONTEXT)
    else
      @proxy.unregister!
      @btnOnOff.setText(OFFTEXT)
    end
  end

  def routesOnClick
    srvlet = @proxy.get_servlet @lstRoutes.getSelectedValue
    if srvlet
      @txtURL.setText((srvlet.path.is_a?(Regexp) ? srvlet.path.inspect : srvlet.path))
      @txtArea.setText(srvlet.text)
    end
  end

  java_import 'javax.swing.DefaultListModel'
  def removeOnClick
    if @txtURL.getText.to_s[0] == '/' #regex
      @proxy.remove_servlet makeRegex(@txtURL.getText)
    else #string
      @proxy.remove_servlet @txtURL.getText.to_s
    end
    a = DefaultListModel.new
    @proxy.routes {|r| a.addElement(r)}
    @lstRoutes.setModel a
  rescue RegexpError, SyntaxError => e
    errorMessage(e.message)
    puts_err e.message
    puts_err e.backtrace
  end

  def insertOnClick
    if @txtURL.getText.to_s[0] == '/' #regex
      @proxy.add_servlet @txtArea.getText, makeRegex(@txtURL.getText)
    else #string
      @proxy.add_servlet @txtArea.getText, @txtURL.getText.to_s
    end
    a = DefaultListModel.new
    @proxy.routes {|r| a.addElement(r)}
    @lstRoutes.setModel a
  rescue RegexpError, SyntaxError => e
    errorMessage(e.message)
    puts_err e.message
    puts_err e.backtrace
  end

  def makeRegex(str)
    options = str.reverse.split('/')[0]
    raise RegexpError, "To many regex options" if options.length > 5
    options.each_char {|c| raise RegexpError, "Invalid regex option character #{c}" unless ['i','m','x','o'].include? c }
    #Still not well validated but YOLO
    eval(str)
  end
end

class BurpExtender
  include IBurpExtender

  ExtensionName = File.basename(__FILE__)[0..-4]

  def registerExtenderCallbacks(callbacks)
    callbacks.setExtensionName ExtensionName
    MainTab.extenderCallbacks = callbacks
    ProxyServer.extenderCallbacks = callbacks
    callbacks.addSuiteTab MainTab.new(ExtensionName)
  end

end