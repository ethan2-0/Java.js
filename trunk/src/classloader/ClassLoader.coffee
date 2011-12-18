messenger = this

class this.ClassLoader
  classReader : 1
  stack : new Array
  ps_id : 0
  required_classes : {}
  #  'java/lang/Class' 

  ###
  Constructor 
  Set runtime data area and grab console from global scope
  ###
  constructor : () ->
    @console = { println : -> yes}
    @find @required_classes
  
  ###
  doAction : (message) -> 
    
    switch message.action
      when 'start' then @start()
      when 'find' then @find(message.param, message.waitingThreads)
  ### 

  ###
  Starts the Classloader, calls load evey 10th of a second
  ###
  start : (JVM) ->
    self = this
    @ps_id = setInterval((() ->  self.load()), 100)

  ###
  Adds a class to the load stack
  ###
  add : (hexstream, name, waitingThreads) ->
    this.stack.push { 
      name : name,
      data : hexstream,
      'waitingThreads' : waitingThreads      
    }
    #messenger.postMessage( { 'action' : 'log', 'message' : 'Class added to stack for loading', 'data' : { 'name' : name, 'waitingThreads': waitingThreads }} )

  ###
  Steps through the class stack and loads each entry into the method area of the RDA.
  ###
  load : ->
    until (next = @stack.pop()) is `undefined`
     #if @RDA.method_area[next.name]? then return true
     if !next.data? or next.data.length < 10 then throw 'InvalidClassException' 
			
     classReader = new ClassReader next.data 
     classReader.parse(@loaded, this, next.waitingThreads)
     
    true

  ### 
  Callback method to execute when class has finished loading.
  Neccessary due to Async AJAX request during find
  Adds class to Method Area and loads class dependancies
  ###
  loaded : (_class, self, waitingThreads) ->
    # load dependancies, this way super class Object will always be the first class loaded.
    self.find _class.get_super()
    
    # notify JVM that class has been loaded
    messenger.postMessage( { 'action' : 'class', 'classname' : _class.get_name(), '_class' : _class, 'waitingThreads' : waitingThreads} )
 
    yes
    
  ###
  Finds a class on the classpath
  ###
  find : (class_name, waitingThreads = false) ->
    throw JSON.stringify(class_name)
    #messenger.postMessage( { 'action' : 'log', 'message' : class_name + ' waiting? ' + waitingThreads })
    # java/lang/Object super class will be undefined
    if typeof class_name is 'undefined'
      return 
    req = new XMLHttpRequest();
    req.open 'GET', "../../classes/rt/#{class_name}.class", false
    # The following line says we want to receive data as Binary and not as Unicode
    req.overrideMimeType 'text/plain; charset=x-user-defined'
    req.send null
    if req.status isnt 200
      req.open 'GET', "../../classes/#{class_name}.class", false
      req.overrideMimeType 'text/plain; charset=x-user-defined'
      req.send null
      if req.status isnt 200
        throw 'NoClassDefFoundError'
    return @add req.responseText, class_name, waitingThreads

 
    
    
###
ClassReader
###
class ClassReader
    
  constructor : (stream) ->
    @binaryReader = new jDataView stream
    @binaryReader._littleEndian = false
    @console = { println : -> yes 
    writeConstant : -> yes}
    
  parse : (whenFinished, classLoader, waitingThreads) ->
    _class = new JavaClass()  
    @parseClassVars _class 
    @parseConstantPool _class
    @parseFileVars _class
    @parseInterfaces _class
    @parseFields _class
    @parseMethods _class
    whenFinished _class, classLoader, waitingThreads

  read : (length) ->
    switch length
      when 1
        @binaryReader.getUint8()
      when 2
        @binaryReader.getUint16()
      when 4 
        @binaryReader.getUint32() 
      else 
        # Probably something not implemented, step forward
        @binaryReader.seek(@binaryReader.tell() + length)
  
  readDouble : ->
    @binaryReader.getFloat32()
    
  readString : (length) ->
    @binaryReader.getString length
    
  readTag : ->
    @read 1

  readConstant : (tag) ->
    switch tag
      when 1 # UTF-8 String 
        @readString(@read 2) 
      when 3, 4 # Integer, Float
        @binaryReader.getUint32()
      when 5, 6 # Long, Double
        @binaryReader.getFloat64()
      when 7, 8 # Class Reference, String Reference
        @read 2 
      when 9, 10, 12 # Field Reference, Method Reference, Name and Type Descriptor
        r1 = @read 2
        r2 = @read 2
        return [r1, r2]
      when 11 # Interface method
        @read 4
      else
        throw "UnknownConstantException, Offset : " + @binaryReader.tell()

  parseClassVars : (_class) ->
    @console.println('magic number: ' + _class.magic_number = @read(4), 2) 
    valid = _class.magic_number.toString(16) & 0xCAFEBABE 
    if valid isnt 0 then alert("Not JavaClass")
    @console.println('minor version: ' + _class.minor_version = @read(2), 2)
    @console.println('major version: ' + _class.major_version = @read(2), 2)
    yes

  parseConstantPool : (_class) ->
    
    #constantPoolCount = parseInt @read(2), 16
    #cp = parseInt(constantPoolCount)
    _class.constant_pool_count = @read 2
    i = 0
    @console.println("Constant Pool Count : #{_class.constant_pool_count}", 2)
    while ++i < _class.constant_pool_count 
      tag = @readTag()
      constant = @readConstant(tag)
      _class.constant_pool[i] = constant
      @console.writeConstant(i, tag, constant, 2)
      if tag is 5 then i++;
      else if tag is 7 
        if constant isnt _class.this_class
          _class.dependancies.push(constant)
        
    yes
	
  parseFileVars : (_class) ->
    @console.println('access flags: '+_class.access_flags = @read(2), 2)
    @console.println('this class: '+_class.this_class = @read(2), 2)
    _class.super_class = @read(2)
    @console.println('super class: '+_class.super_class, 2)
    _class.real_name = _class.constant_pool[_class.constant_pool[_class.this_class]]
    yes
   
  parseInterfaces : (_class) ->
    @console.println('interface count: ' +_class.interfaces_count = @read(2), 2)
    i = -1
    while ++i < _class.interfaces_count
      @console.println _class.interfaces[i] = @read(2), 2
    yes
    
  parseFields : (_class) ->
    @console.println 'fields count: ' + _class.fields_count = @read(2), 2
    i = -1
    while ++i < _class.fields_count
      field = @readFieldInfo(_class)
      _class.fields[field.real_name] = field
    yes
    
  parseMethods : (_class) ->
    @console.println 'method count: ' + _class.method_count = @read(2), 2
    i = -1
    while ++i < _class.method_count
      method = @readMethodInfo _class
      _class.methods[_class.constant_pool[method.name_index]] = method 
    yes   
   	
  parseAttributes : (_class) ->
    _class.attributes_count(@read 2)
  
  readMethodInfo : (_class) ->
    method_info = {}
    @console.println '  access flags: ' + method_info.access_flags = @read(2), 2;
    @console.println '  name index: ' + method_info.name_index = @read(2), 2;
    method_info.name = _class.constant_pool[method_info.name_index];
    @console.println '  descriptor index: ' + method_info.descriptor_index = @read(2), 2;
    @console.println '  atrribute count: ' + method_info.attribute_count = @read(2), 2;
   	method_info.attributes = new Array(method_info.attribute_count);
    i = 0
    while i++ < method_info.attribute_count
      attr = @readAttribute _class
      method_info.attributes[attr.real_name] = attr
    method_info
        
  readAttribute : (_class) ->
    attribute_name = @read 2
    attribute_length = @read 4
    real_name = _class.constant_pool[attribute_name]
    @console.println '    attribute name: ' + real_name, 2
    @console.println '    attribute length: ' + attribute_length, 2
    if real_name is 'Code'
      return @readCodeAttribute(_class, attribute_name, attribute_length)
    else
      @read attribute_length
      return {}

    
  readCodeAttribute : (_class, name_index, length) ->
    code_attribute = {}
    code_attribute.attribute_name_index = name_index
    code_attribute.real_name = _class.constant_pool[name_index]
    code_attribute.attribute_length = length
    code_attribute.max_stack = @read 2
    code_attribute.max_locals = @read 2
    code_attribute.code_length = @read 4
    code_attribute.code = {};
    code_length = code_attribute.code_length
    i = -1
    while ++i < code_length
        @console.println('      ' +(code_attribute.code[i] = @read(1)), 2)
    code_attribute.exception_table_length = @read 2
    # TODO exception table
    @read(code_attribute.exception_table_length*8)
    code_attribute.attributes_count = @read 2
   	code_attribute.attributes = new Array(code_attribute.attributes_count)
    i = -1
    while ++i < code_attribute.attributes_count
        code_attribute.attributes[i] = @readAttribute(_class)
    return code_attribute;
    
  readFieldInfo : (_class) ->
    field_info = {}
    @console.println '  access flags: ' + field_info.access_flags = @read(2), 2
    @console.println '  name index: ' + field_info.name_index = @read(2), 2
    @console.println '  descriptor index: ' + field_info.descriptor_index = @read(2), 2
    @console.println '  atrribute count: ' + field_info.attribute_count = @read(2), 2
   	field_info.attributes = new Array(field_info.attribute_count);
   	field_info.real_name = _class.constant_pool[field_info.name_index]
    i = 0
    while i++ < field_info.attribute_count
      field_info.attributes[i] = @readAttribute _class
    field_info


###
Represents a Java Class file. Also provides Class verification methods.
@returns {JavaClass}
###

class this.JavaClass 
  constructor : () ->
    @magic_number = 0
    @minor_version = 0
    @major_version = 0
    @constant_pool_count = 0
    @constant_pool = []
    @access_flags = 0
    @this_class = 0
    @super_class = 0
    @interfaces_count = 0
    @interfaces = []
    @fields_count = 0
    @fields = []
    @methods_count = 0
    @methods = []
    @attributes_count = 0
    @attributes = []
    @dependancies = []
    @real_name = 'None'
        
  get_super : -> 
    super_ref = @constant_pool[@super_class];
    @constant_pool[super_ref];
  
  get_name : ->
    super_ref = @constant_pool[@this_class];
    @constant_pool[super_ref];
    
  set_method_count : (count) -> 
    @methods_count = parseInt count, 16
    @methods = new Array parseInt count, 16
    return count
  
  set_constant_pool_count : (count) -> 
    @constant_pool_count = parseInt count, 16
    @constant_pool = new Array parseInt count, 16
    return count
    
  set_interfaces_count : (count) ->
    @interfaces_count = parseInt count, 16
    @interfaces = new Array parseInt count, 16
    return count
  
  set_fields_count : (count) ->
    @fields_count = parseInt count, 16
    @fields = new Array parseInt count, 16
    return count
    
  set_attributes_count : (count) ->
    @attributes_count = parseInt count, 16
    @attributes = new Array parseInt count, 16
    return count
    
classLoader = new ClassLoader()
@onmessage = (e) -> 
  throw e.data.param
  classLoader.find e.data.param, e.data.waitingThreads
  yes
  #classLoader.start()


`
compatibility = {
ArrayBuffer: typeof ArrayBuffer !== 'undefined',
DataView: typeof DataView !== 'undefined' && 'getFloat64' in DataView.prototype
}

jDataView = function (buffer, byteOffset, byteLength, littleEndian) {
this._buffer = buffer;

// Handle Type Errors
if (!(compatibility.ArrayBuffer && buffer instanceof ArrayBuffer) &&
!(typeof buffer === 'string')) {
throw new TypeError("Type error");
}

// Check parameters and existing functionnalities
this._isArrayBuffer = compatibility.ArrayBuffer && buffer instanceof ArrayBuffer;
this._isDataView = compatibility.DataView && this._isArrayBuffer;

// Default Values
this._littleEndian = littleEndian === undefined ? true : littleEndian;

var bufferLength = this._isArrayBuffer ? buffer.byteLength : buffer.length;
if (byteOffset == undefined) {
byteOffset = 0;
}

if (byteLength == undefined) {
byteLength = bufferLength - byteOffset;
}

if (!this._isDataView) {
// Do additional checks to simulate DataView
if (typeof byteOffset !== 'number') {
throw new TypeError("Type error");
}
if (typeof byteLength !== 'number') {
throw new TypeError("Type error");
}
if (typeof byteOffset < 0) {
throw new Error("INDEX_SIZE_ERR: DOM Exception 1");
}
if (typeof byteLength < 0) {
throw new Error("INDEX_SIZE_ERR: DOM Exception 1");
}
}

// Instanciate
if (this._isDataView) {
this._view = new DataView(buffer, byteOffset, byteLength);
this._start = 0;
}
this._start = byteOffset;
if (byteOffset >= bufferLength) {
throw new Error("INDEX_SIZE_ERR: DOM Exception 1");
}

this._offset = 0;
this.length = byteLength;
};

jDataView.createBuffer = function () {
if (typeof ArrayBuffer !== 'undefined') {
var buffer = new ArrayBuffer(arguments.length);
var view = new Int8Array(buffer);
for (var i = 0; i < arguments.length; ++i) {
view[i] = arguments[i];
}
return buffer;
}

return String.fromCharCode.apply(null, arguments);
};

jDataView.prototype = {

// Helpers

getString: function (length, byteOffset) {
var value;

// Handle the lack of byteOffset
if (byteOffset === undefined) {
byteOffset = this._offset;
}

// Error Checking
if (typeof byteOffset !== 'number') {
throw new TypeError("Type error");
}
if (length < 0 || byteOffset + length > this.length) {
throw new Error("INDEX_SIZE_ERR: DOM Exception 1");
}

if (this._isArrayBuffer) {
// Use Int8Array and String.fromCharCode to extract a string
var int8array = new Int8Array(this._buffer, this._start + byteOffset, length);
var stringarray = [];
for (var i = 0; i < length; ++i) {
stringarray[i] = int8array[i];
}
value = String.fromCharCode.apply(null, stringarray);
} else {
value = this._buffer.substr(this._start + byteOffset, length);
}

this._offset = byteOffset + length;
return value;
},

getChar: function (byteOffset) {
var value, size = 1;

// Handle the lack of byteOffset
if (byteOffset === undefined) {
byteOffset = this._offset;
}

if (this._isArrayBuffer) {
// Use Int8Array and String.fromCharCode to extract a string
value = String.fromCharCode(this.getUint8(byteOffset));
} else {
// Error Checking
if (typeof byteOffset !== 'number') {
throw new TypeError("Type error");
}
if (byteOffset + size > this.length) {
throw new Error("INDEX_SIZE_ERR: DOM Exception 1");
}

value = this._buffer.charAt(this._start + byteOffset);
this._offset = byteOffset + size;
}

return value;
},

tell: function () {
return this._offset;
},

seek: function (byteOffset) {
if (typeof byteOffset !== 'number') {
throw new TypeError("Type error");
}
if (byteOffset < 0 || byteOffset > this.length) {
throw new Error("INDEX_SIZE_ERR: DOM Exception 1");
}

this._offset = byteOffset;
},

// Compatibility functions on a String Buffer

_endianness: function (offset, pos, max, littleEndian) {
return offset + (littleEndian ? max - pos - 1 : pos);
},

_getFloat64: function (offset, littleEndian) {
var b0 = this._getUint8(this._endianness(offset, 0, 8, littleEndian)),
b1 = this._getUint8(this._endianness(offset, 1, 8, littleEndian)),
b2 = this._getUint8(this._endianness(offset, 2, 8, littleEndian)),
b3 = this._getUint8(this._endianness(offset, 3, 8, littleEndian)),
b4 = this._getUint8(this._endianness(offset, 4, 8, littleEndian)),
b5 = this._getUint8(this._endianness(offset, 5, 8, littleEndian)),
b6 = this._getUint8(this._endianness(offset, 6, 8, littleEndian)),
b7 = this._getUint8(this._endianness(offset, 7, 8, littleEndian)),

sign = 1 - (2 * (b0 >> 7)),
exponent = ((((b0 << 1) & 0xff) << 3) | (b1 >> 4)) - (Math.pow(2, 10) - 1),

// Binary operators such as | and << operate on 32 bit values, using + and Math.pow(2) instead
mantissa = ((b1 & 0x0f) * Math.pow(2, 48)) + (b2 * Math.pow(2, 40)) + (b3 * Math.pow(2, 32))
+ (b4 * Math.pow(2, 24)) + (b5 * Math.pow(2, 16)) + (b6 * Math.pow(2, 8)) + b7;

if (mantissa == 0 && exponent == -(Math.pow(2, 10) - 1)) {
return 0.0;
}

if (exponent == -1023) { // Denormalized
return sign * mantissa * Math.pow(2, -1022 - 52);
}

return sign * (1 + mantissa * Math.pow(2, -52)) * Math.pow(2, exponent);
},

_getFloat32: function (offset, littleEndian) {
var b0 = this._getUint8(this._endianness(offset, 0, 4, littleEndian)),
b1 = this._getUint8(this._endianness(offset, 1, 4, littleEndian)),
b2 = this._getUint8(this._endianness(offset, 2, 4, littleEndian)),
b3 = this._getUint8(this._endianness(offset, 3, 4, littleEndian)),

sign = 1 - (2 * (b0 >> 7)),
exponent = (((b0 << 1) & 0xff) | (b1 >> 7)) - 127,
mantissa = ((b1 & 0x7f) << 16) | (b2 << 8) | b3;

if (mantissa == 0 && exponent == -127) {
return 0.0;
}

if (exponent == -127) { // Denormalized
return sign * mantissa * Math.pow(2, -126 - 23);
}

return sign * (1 + mantissa * Math.pow(2, -23)) * Math.pow(2, exponent);
},

_getInt32: function (offset, littleEndian) {
var b = this._getUint32(offset, littleEndian);
return b > Math.pow(2, 31) - 1 ? b - Math.pow(2, 32) : b;
},

_getUint32: function (offset, littleEndian) {
var b3 = this._getUint8(this._endianness(offset, 0, 4, littleEndian)),
b2 = this._getUint8(this._endianness(offset, 1, 4, littleEndian)),
b1 = this._getUint8(this._endianness(offset, 2, 4, littleEndian)),
b0 = this._getUint8(this._endianness(offset, 3, 4, littleEndian));

return (b3 * Math.pow(2, 24)) + (b2 << 16) + (b1 << 8) + b0;
},

_getInt16: function (offset, littleEndian) {
var b = this._getUint16(offset, littleEndian);
return b > Math.pow(2, 15) - 1 ? b - Math.pow(2, 16) : b;
},

_getUint16: function (offset, littleEndian) {
var b1 = this._getUint8(this._endianness(offset, 0, 2, littleEndian)),
b0 = this._getUint8(this._endianness(offset, 1, 2, littleEndian));

return (b1 << 8) + b0;
},

_getInt8: function (offset) {
var b = this._getUint8(offset);
return b > Math.pow(2, 7) - 1 ? b - Math.pow(2, 8) : b;
},

_getUint8: function (offset) {
if (this._isArrayBuffer) {
return new Uint8Array(this._buffer, this._start + offset, 1)[0];
} else {
return this._buffer.charCodeAt(this._start + offset) & 0xff;
}
}
};

// Create wrappers

var dataTypes = {
'Int8': 1,
'Int16': 2,
'Int32': 4,
'Uint8': 1,
'Uint16': 2,
'Uint32': 4,
'Float32': 4,
'Float64': 8
};

for (var type in dataTypes) {
// Bind the variable type
(function (type) {
var size = dataTypes[type];

// Create the function
jDataView.prototype['get' + type] = 
function (byteOffset, littleEndian) {
var value;

// Handle the lack of endianness
if (littleEndian == undefined) {
littleEndian = this._littleEndian;
}

// Handle the lack of byteOffset
if (byteOffset === undefined) {
byteOffset = this._offset;
}

// Dispatch on the good method
if (this._isDataView) {
// DataView: we use the direct method
value = this._view['get' + type](byteOffset, littleEndian);
}
// ArrayBuffer: we use a typed array of size 1 if the alignment is good
// ArrayBuffer does not support endianess flag (for size > 1)
else if (this._isArrayBuffer && byteOffset % size == 0 && (size == 1 || littleEndian)) {
value = new self[type + 'Array'](this._buffer, byteOffset, 1)[0];
}
else {
// Error Checking
if (typeof byteOffset !== 'number') {
throw new TypeError("Type error");
}
if (byteOffset + size > this.length) {
throw new Error("INDEX_SIZE_ERR: DOM Exception 1");
}
value = this['_get' + type](this._start + byteOffset, littleEndian);
}

// Move the internal offset forward
this._offset = byteOffset + size;

return value;
};
})(type);
}`


