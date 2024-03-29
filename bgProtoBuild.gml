/*
by		: BahamaGames / rickky
GMail	: bahamagames@gmail.com 
Discord	: rickky#1696
GitHub	: https://github.com/BahamaGames

Credits : Maseta. Base was made from his protobuild. https://meseta.itch.io/lockstep
*/

//		Feather disable GM2017 Inconsistent naming
//		Feather disable GM1041 Passing struct to Id.Instance 
//		Feather disable GM1042 Parameter naming convention
//		Feather disable GM1063
//		Feather disable GM1044
//		Feather disable GM2044

/// @context										bgProtoBuild
/// @description									Builds proto messages / buffers to be used for rpcs. Most methods can be chained to utilize the internal write buffer,
///													and current message feature. You may provide a config struct to modify the protocol.
///														code		: {Real} 						A unique code within the range of 0 - 65533 used to identify the protocol, 
///																									verify connection, and packets. Note 65534 is used for custom protocol 
///																									entry point that you may provide, and 65535 is for internal secondary protocol.

///														interceptor	: {Function(callback, packet)} 	A function that intercepts a callback during decode methods. Return true to 
///																									execute, and false to skip. Does not apply to custom protocol.

///														protocol	: {Function(async_load)} 		A function that is executed if the protocol code is 65534. Buffer size 
///																									(in bytes) must be greater than 4 to account for internal headers before being
///																									sent, and the offset will be at 2 upon read which was read to determine the protocol
///																									code. It should also be noted this function should be treated as if being called
///																									within the async network event. DO NOT DESTROY THE DS MAP NOR DELETE THE BUFFER!!!
///																									If using a tcp related protocol you must read the entirety of the custom buffer
///																									you sent. NOT the actual size of the buffer stored within async_load_[? "size"] or 
///																									returned by buffer_get_size(), as the buffer may contain additional bytes from previous
///																									packets, or potentially new ones. Check <bgPacketizeCustomStream> for help with tcp stream.

/// @param {Struct}					protoConfig		- Configuration struct for protobuild.
/// @param {Struct}					loggerConfig	- Configuration struct for bgLogger if present.
function bgProtoBuild(__bg_config = {"code": 0xAE1B, "interceptor": undefined, "protocol": undefined}, __bg_logger_config = {}) : bgLogger(__bg_logger_config) constructor
{
	/*
	All accessiable variables, and methods are abbrivated with bg
	to avoid conflicts with other projects.
	
	All variables are to be used for READONLY purposes if wishs to write
	simply make a copy, and use that.
	*/
	bg_proto_code					= __bg_config[$ "code"]			?? 0xAE1B;
	_bg_custom_protocol				= __bg_config[$ "protocol"]		?? bg_blank_callback;
	_bg_callback_interceptor		= __bg_config[$ "interceptor"]	?? function(__bg_callback, __bg_packet) {return true};
	
	bg_hash							= "";
	bg_msg_specs					= {};
	bg_msg_current					= "";
	_bg_msg_id						= 0;
	_bg_secondary_protocol_array	= [];
	_bg_secondary_protocol_length	= 0;
	_bg_msg_array					= array_create(65535, undefined);
	_bg_write_buffer				= buffer_create(1, buffer_grow, 1);
	_bg_read_buffers 				= array_create(65535, undefined);
	_bg_async_load					= ds_map_create();
	
	//Protocol code to be used for custom messages.
	#macro bgCustomProtocol			65534
	
	#macro bgNewBuffer				-2
	#macro bgWriteBuffer			-1
	
	/*
	Values from 65512-65530 in respective order are reserved 
	for read and writes. It's recommended to use bgText, or 
	bgBuffer to write any value that are not within the range
	of any of the bg* buffer types due to possibe changes.
	bgText is capped at a 65535 length, and bgBuffer 4294967295.
	Beware of mtu.
	*/
	
	#macro bgAssetScript			0xFFE8
	#macro bgAssetPath				0xFFE9
	#macro bgAssetObject			0xFFEA
	#macro bgAssetSprite			0xFFEB
	#macro bgConstruct				0xFFEC
	#macro bgJson					0xFFED
	#macro bgBool					0xFFEE
	#macro bgU8						0xFFEF
	#macro bgS8						0xFFF0
	#macro bgU16					0xFFF1
	#macro bgS16					0xFFF2
	#macro bgF16					0xFFF3
	#macro bgU32					0xFFF4
	#macro bgS32					0xFFF5
	#macro bgF32					0xFFF6
	#macro bgU64					0xFFF7
	#macro bgF64					0xFFF8
	#macro bgText					0xFFF9
	#macro bgBuffer					0xFFFA
	
	/// @context								self
	/// @function								bgGetMsgId()
	/// @description							Returns the protomessage id tracker.
	/// @return   {Real}
	static bgGetMsgId				= function()
	{
		return _bg_msg_id;
	}
	
	/// @context								self								
	/// @function								bgSetMsgId(id)
	/// @description							Sets the protomessage id tracker.
	/// @param	 {Real}				id			- Id to assign to protomessage must be within the range 0 - 65535.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSetMsgId				= function(__bg_id)
	{
		_bg_msg_id = __bg_id;
		return self;
	}
	
	/// @context								self								
	/// @function								bgMsgCreate(msgName, callback, id)
	/// @description							Creates a new proto message with an optional callback. Returns the protobuild interface thus can be chained.
	/// @param   {string}			msgName		- Proto message name.
	/// @param   {Function}			callback	- Function of callback handler to trigger when recieving this message.
	/// @param	 {Real}				id			- Id to assign to protomessage must be within the range 0 - 65535.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgMsgCreate				= function(__bg_msg_name, __bg_callback = bg_blank_callback, __bg_id = _bg_msg_id)
	{
		if(argument_count < 1)
		{
			bgWarn("Invalid argument amount");
			return self;
		}
		
		if(_bg_msg_array[__bg_id] != undefined)
		{
			bgWarn("Invalid id already in use");
			return self;
		}
		
		if(bg_msg_specs[$ __bg_msg_name] == undefined)
		{
			var __bg_msg					= {
				bg_id						: __bg_id,
				bg_name						: __bg_msg_name,
				bg_specs					: [],
				bg_types					: [],
				bg_size						: 0,
				bg_value					: 0,
				bg_callback					: __bg_callback,
				bg_callback_str				: __bg_callback != bg_blank_callback? script_get_name(__bg_callback): ""
			}
			
			_bg_msg_id						= __bg_id + 1;
			bg_msg_specs[$ __bg_msg_name]	= __bg_msg;
			_bg_msg_array[__bg_id]			= __bg_msg;
			bg_msg_current					= __bg_msg_name;
			
			return self;
		}else bgWarn(__bg_msg_name + " was already added");
	}
	
	/// @context								self
	/// @function								bgSetCurrentMsg(msgName)
	/// @description							Sets the current proto message context. Useful for when chaining. Returns the protobuild interface thus can be chained.
	/// @param   {string}			msgName		- Proto message name.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSetCurrentMsg			= function(__bg_msg_name)
	{
		bg_msg_current = __bg_msg_name;
		
		return self;
	}
	
	/// @context								self
	/// @function								bgMsgAddSpec(valName, valType, valDefault)
	/// @description							Adds a spec/value to the current proto message. +2 Overload.
	///											bgMsgAddSpec(valName, valType, valDefault)
	///											bgMsgAddSpec(msgName, valName, valType, valDefault)
	///											Returns the protobuild interface thus can be chained
	/// @param   {string}			valName		- Name of the value to be added.
	/// @param	   {Real}			valType		- Type of value. Can be of any number value greater than 0, but less than bgBuffer.
	/// @param		{any}			valDefault	- Default value to be used when encoding from struct.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgMsgAddSpec				= function()
	{
		var 
		__bg_val_name,
		__bg_val_type,
		__bg_val_default;
		
		if(argument_count == 3)
		{
			__bg_val_name	= argument[0];
			__bg_val_type	= argument[1];
			__bg_val_default= argument[2];
		}else{
			bg_msg_current	= argument[0];
			__bg_val_name	= argument[1];
			__bg_val_type	= argument[2];
			__bg_val_default= argument[3];
		}
		
		var __bg_msg = bg_msg_specs[$ bg_msg_current];
		if(__bg_msg == undefined) bgFatal("Msg spec",bg_msg_current,"does not exist");
		else{
			var __bg_specs = __bg_msg.bg_specs;
			
			for(var i = 0, s = __bg_msg.bg_value; i < s; ++i)
			{
				var __bg_check = __bg_specs[i];
				if(__bg_check.bg_name == __bg_val_name)
				{
					bgWarn(__bg_val_name, "in", bg_msg_current, "already exists");
					return self
				}
			}
			
			var __bg_size = __bg_msg.bg_size;
			
			switch(__bg_val_type) 
			{
				case bgBool:
				case bgU8:
				case bgS8:
					__bg_size += 1;
					break;
				case bgAssetSprite:
				case bgAssetObject:
				case bgText:
				case bgJson:
				case bgConstruct:
				case bgU16:
				case bgS16:
				case bgF16:
					__bg_size += 2;
					break;
				case bgBuffer:
				case bgU32:
				case bgS32:
				case bgF32:
					__bg_size += 4;
					break;
				case bgU64:
				case bgF64:
					__bg_size += 8;
					break;
				case 0:
					bgFatal("Attempting to add a value size of zero within message", bg_msg_current, "at", __bg_val_name);
					return self;
				default:
					if(__bg_val_type >= bgText - 1)
					{
						bgFatal("Attempting to add a value greater than or equal to", bgText - 1,"within message", bg_msg_current, "at", __bg_val_name);
						return self;
					}
					__bg_size += __bg_val_type;
			}
			
			__bg_msg.bg_size = __bg_size;
			
			array_push(__bg_msg.bg_types, __bg_val_type);
			
			array_push(__bg_specs, {
				bg_name		: __bg_val_name,
				bg_type		: __bg_val_type,
				bg_default	: __bg_val_default
			});
			
			__bg_msg.bg_value++;
		}
		return self;
	}
	
	/// @context								self
	/// @function								bgMsgUpdateCallback(msgName, callback)
	/// @description							Updates the callback of a pre existing proto message, also sets the current message. Returns the protobuild interface thus can be chained.
	/// @param	  {string}			msgName		- Proto message name.
	/// @param    {Function}		callback	- Function handler to trigger when recieving the proto message.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgMsgUpdateCallback		= function(__bg_msg_name, __bg_callback)
	{
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		if(__bg_msg == undefined)
		{
			bgFatal(__bg_msg_name, "does not exist");
			return self;
		}
		__bg_msg.bg_callback     = __bg_callback;
		__bg_msg.bg_callback_str = script_get_name(__bg_callback);
		_bg_msg_current			 = __bg_msg_name;
		return self	
	}
	
	/// @context								self
	/// @function								bgGetMsg(msgName)
	/// @description							Returns a previously created proto message.
	/// @param	  {string}			msgName		- Proto message name. Default: current proto message would be used.
	/// @return   {Struct}			Returns the - proto message specs.
	static bgGetMsg					= function(__bg_msg_name = bg_msg_current)
	{
		return bg_msg_specs[$ __bg_msg_name]
	}
	
	/// @context								self
	/// @function								bgGetCurrentMsg()
	/// @description							Returns the current msg set.
	/// @return   {String}						Returns the current msg set.
	static bgGetCurrentMsg			= function()
	{
		return bg_msg_current;	
	}
	
	/// @context								self
	/// @function								bgSetMsgSize(msgName, size)
	/// @description							Sets a message's size. Usefull for previously unknown message sizes. +1 Overload
	///											.bgSetMsgSize(msgName, size),
	///											.bgSetMsgSize(size). Returns the protobuild interface thus can be chained.
	/// @param    {string}			*msgName	- Proto message name. Default: current proto message would be used.
	/// @param	    {Real}			new_size	- Size to assign to message.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSetMsgSize				= function(__bg_msg_name, __bg_size)
	{
		if(argument_count == 1)
		{
			__bg_size		= __bg_msg_name;
			__bg_msg_name	= bg_msg_current;
		}
		var 
		__bg_msg = bg_msg_specs[$ __bg_msg_name],
		__bg_arr = __bg_msg.bg_types;
		for(var i = 0, s = array_length(__bg_arr); i < s; ++i)
		{
			var __bg_spec_type = __bg_arr[i];
		    switch(__bg_spec_type) 
			{
		        case bgBool:
		        case bgU8:
		        case bgS8:
		            __bg_size += 1;
		            break;
				case bgAssetScript: case bgAssetSprite: case bgAssetPath: case bgAssetObject:
				case bgText:
				case bgJson:
				case bgConstruct:
		        case bgU16:
		        case bgS16:
				case bgF16:
		            __bg_size += 2;
		            break;
				case bgBuffer:
		        case bgU32:
		        case bgS32:
		        case bgF32:
		            __bg_size += 4;
		            break;
		        case bgU64:
		        case bgF64:
		            __bg_size += 8;
		            break;
				case 0:
					bgFatal("Attempting to add a value size of zero within message", __bg_msg_name);
					return self;
				default:
					if(__bg_spec_type >= bgText - 1)
					{
						bgFatal("Attempting to add a value greater than or equal to", bgText - 1,"within message", __bg_msg_name);
						return self;
					}
					__bg_size += __bg_spec_type;
		    }
		}
		__bg_msg.bg_size	= __bg_size;
		bg_msg_current		= __bg_msg_name;
		return self;
	}
	
	/// @context								self
	/// @function								bgGetMsgSize(msgName)
	/// @description							Gets the size of a pre existing proto message.
	/// @param    {string}			*msgName	- Proto message name. Default: current message would be used.
	/// @return     {Real}						Returns the size of the message.
	static bgGetMsgSize				= function(__bg_msg_name = bg_msg_current)
	{
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		
		if(__bg_msg == undefined)
		{
			bgFatal("message", __bg_msg_name, "not found");
			return -1;
		}
		
		return __bg_msg.bg_size + 2;
	}
	
	/// @context								self
	/// @function								bgGetAllMsg()
	/// @description							Returns all proto messages cached.
	/// @return	  {Struct}						Returns all proto messages cached.
	static bgGetAllMsg				= function()
	{
		return bg_msg_specs;
	}
	
	/// @context								self
	/// @function								bgEncodeValue(bufferid, bgType, value(s))
	/// @description							Encodes a buffer using proto message. Returns the protobuild interface thus can be chained.
	/// @param	{Id.Buffer}			bufferid	- Buffer index to write to.
	/// @param {Constant.bgType}	bgType		- Type of bgBuffer to convert to gml buffer_*.
	/// @param		 {any}			value(s)	- Sequential value(s) to write to buffer.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgEncodeValue			= function(__bg_buff, __bg_type, __bg_insert_val)
	{
		switch(__bg_type)
		{
			case bgBool: case bgU8:
				buffer_write(__bg_buff, buffer_u8, __bg_insert_val);
				break;
			case bgS8:
				buffer_write(__bg_buff, buffer_s8, __bg_insert_val);
				break;
			case bgU16:
				buffer_write(__bg_buff, buffer_u16, __bg_insert_val);
				break;
			case bgS16:
				buffer_write(__bg_buff, buffer_s16, __bg_insert_val);
				break;
			case bgF16:
				buffer_write(__bg_buff, buffer_f16, __bg_insert_val);
				break;
			case bgU32:
				buffer_write(__bg_buff, buffer_u32, __bg_insert_val);
				break;
			case bgS32:
				buffer_write(__bg_buff, buffer_s32, __bg_insert_val);
				break;
			case bgF32:
				buffer_write(__bg_buff, buffer_f32, __bg_insert_val);
				break;
			case bgU64:
				buffer_write(__bg_buff, buffer_u64, __bg_insert_val);
				break;
			case bgF64:
				buffer_write(__bg_buff, buffer_f64, __bg_insert_val);
				break;
			case bgConstruct:
				var 
				__bg_protobuild = self,
				__bg_size		= buffer_tell(__bg_buff);
				with(__bg_insert_val)
				{
					var 
					__bg_schema = __bg_protobuild.bg_msg_specs[$ bg_struct],
					__bg_defini = __bg_schema.bg_specs;
					
					buffer_write(__bg_buff, buffer_u32, 0);
					buffer_write(__bg_buff, buffer_string, bg_struct);
					
					for(var i	= __bg_schema.bg_value - 1; i >= 0; --i)
					{
						var __bg_spec = __bg_defini[i];
						__bg_protobuild.bgEncodeValue(__bg_buff, __bg_spec.bg_type, self[$ __bg_spec.bg_name]);
					}
					
					buffer_poke(__bg_buff, __bg_size, buffer_u32, buffer_tell(__bg_buff) - __bg_size);
				}
				break;
			case bgJson:
				__bg_insert_val = json_stringify(__bg_insert_val);
			case bgAssetSprite:
				__bg_insert_val = !is_real(__bg_insert_val)? __bg_insert_val: sprite_get_name(__bg_insert_val);
			case bgAssetObject:
				__bg_insert_val = !is_real(__bg_insert_val)? __bg_insert_val: object_get_name(__bg_insert_val);
			case bgAssetPath:
				__bg_insert_val = !is_real(__bg_insert_val)? __bg_insert_val: path_get_name(__bg_insert_val);
			case bgAssetScript:
				__bg_insert_val = !is_real(__bg_insert_val)? __bg_insert_val: script_get_name(__bg_insert_val);
			case bgText:
				buffer_write(__bg_buff, buffer_u16, string_length(__bg_insert_val));
				buffer_write(__bg_buff, buffer_text, __bg_insert_val);
				break;
			case bgBuffer:
				var __bg_size = buffer_get_size(__bg_insert_val);
		        buffer_write(__bg_buff, buffer_u32, __bg_size);
				buffer_copy(__bg_insert_val, 0, __bg_size, __bg_buff, buffer_tell(__bg_buff));
				buffer_seek(__bg_buff, buffer_seek_relative, __bg_size);
				break;
			default:
				buffer_fill(__bg_buff, buffer_tell(__bg_buff), buffer_u8, 0, __bg_type);
				buffer_write(__bg_buff, buffer_text, string_copy(__bg_insert_val, 1, __bg_type));
				buffer_seek(__bg_buff, buffer_seek_relative, __bg_type);
		}
		return self;
	}
	
	/// @context								self
	/// @function								bgEncodeDirect(bufferid, msgName, value)
	/// @description							Encodes a buffer using data from arguments. MUST provide all values. Will return false if an issue was detected, else protobuild interface thus can be chained.
	/// @param	{Id.Buffer}			bufferid	- Buffer index to write to. Can enter bgWriteBuffer to use built in write buffer.
	/// @param	  {string}			msgName		- Name of the proto message. Can enter "" to use the current message.
	/// @param		   {any}		value(s)	- Sequential value(s) in message spec.
	/// @return {Any}							Returns the protobuild interface thus can be chained.
	static bgEncodeDirect			= function(__bg_buffer, __bg_msg_name)
	{
		if(argument_count < 2) bgFatal("Invalid amount of arguments");
		if(__bg_msg_name == "") __bg_msg_name = bg_msg_current;
		
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		
		if(__bg_msg == undefined)
		{
			bgWarn("message", __bg_msg_name, "not found");
			return false;
		}
		
		if(__bg_buffer == bgWriteBuffer) __bg_buffer = _bg_write_buffer;
		
		var __bg_types = __bg_msg.bg_types;
		
		buffer_write(__bg_buffer, buffer_u16, __bg_msg.bg_id);
		
		for(var i = 0, s = __bg_msg.bg_value; i < s && i + 2 < argument_count; ++i) bgEncodeValue(__bg_buffer, __bg_types[i], argument[i + 2]);
		
		return self;
	}
	
	/// @context								self
	/// @function								bgEncodeFromStruct(bufferid, msgName, struct)
	/// @description							Encodes a buffer using data from struct. If key is missing default value will be used. Returns the protobuild interface thus can be chained.
	/// @param	{Id.Buffer}			bufferid	- Buffer index to write to. Can enter bgWriteBuffer to use built in write buffer.
	/// @param	  {string}			msgName		- Name of the proto message. Can enter "" to use the current message.
	/// @param	  {Struct}			value		- A struct containing the message key and desired value.
	/// @return {Any}							Returns the protobuild interface thus can be chained.
	static bgEncodeFromStruct		= function(__bg_buff, __bg_msg_name, __bg_struct)
	{
		if(__bg_buff == bgWriteBuffer) __bg_buff= _bg_write_buffer;
		if(__bg_msg_name == "") __bg_msg_name	= bg_msg_current;
		
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		
		if(__bg_msg == undefined)
		{
			bgWarn("message", __bg_msg_name, "not found");
			return false;	
		}
		
		var __bg_specs = __bg_msg.bg_specs;
		
		buffer_write(__bg_buff, buffer_u16, __bg_msg.bg_id);
		
		for(var i = 0, s = __bg_msg.bg_value; i < s; ++i)
		{
			var 
			__bg_spec		= __bg_specs[i],
			__bg_insert_val = __bg_struct[$ __bg_spec.bg_name];
			__bg_insert_val ??= __bg_spec.bg_default;
			
			bgEncodeValue(__bg_buff, __bg_spec.bg_type, __bg_insert_val);
		}
		return self;
	}
	
	/// @context								self
	/// @function								bgDecodeValue(bufferid, specType, object)
	/// @description							Decodes a protospec into a buffer, returning the value. If parse fail value will return undefined.
	/// @param	{Id.Buffer}			bufferid	- Buffer index to decode.
	/// @param {Constant.bgType}	bgType		- Type of buffer to decode a Real value between 1 and bgBuffer.
	/// @param {Struct}				object		- The constructor struct to update directly. Must have the variable bg_struct.
	/// @return {any}				
	static bgDecodeValue			= function(__bg_buffer, __bg_spec_type, __bg_object = undefined)
	{
		var 
		__bg_value	= undefined,
		__bg_buff,
		__bg_r,
		__bg_s;
		
		switch(__bg_spec_type)
		{
			case 0: return 0;
			case bgBool: case bgU8:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 1) __bg_value = buffer_read(__bg_buffer, buffer_u8);
				break;
			case bgS8:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 1) __bg_value = buffer_read(__bg_buffer, buffer_s8);
				break;
			case bgU16:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 2) __bg_value = buffer_read(__bg_buffer, buffer_u16);
				break;
			case bgS16:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 2) __bg_value = buffer_read(__bg_buffer, buffer_s16);
				break;
			case bgF16:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 2) __bg_value = buffer_read(__bg_buffer, buffer_f16);
				break;
			case bgU32:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 4) __bg_value = buffer_read(__bg_buffer, buffer_u32);
				break;
			case bgS32:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 4) __bg_value = buffer_read(__bg_buffer, buffer_s32);
				break;
			case bgF32:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 4) __bg_value = buffer_read(__bg_buffer, buffer_f32);
				break;
			case bgU64:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 8) __bg_value = buffer_read(__bg_buffer, buffer_u64);
				break;
			case bgF64:
				if(buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer) >= 8) __bg_value = buffer_read(__bg_buffer, buffer_f64);
				break;
			case bgJson:
				__bg_r	= buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer);
				
				if(__bg_r < 2) break;
				
				__bg_r -= 2;
				__bg_s	= buffer_read(__bg_buffer, buffer_u16);
				
				if(__bg_r < __bg_s) break;
				
				if(__bg_s > 0)
				{
					__bg_buff = buffer_create(__bg_s, buffer_fixed, 1);
					buffer_copy(__bg_buffer, buffer_tell(__bg_buffer), __bg_s, __bg_buff, 0);
					buffer_seek(__bg_buffer, buffer_seek_relative, __bg_s);					
					try{__bg_value	= json_parse(buffer_read(__bg_buff, buffer_text));}catch(e){__bg_value = undefined;}
					buffer_delete(__bg_buff);
				}
				break;
			case bgConstruct:
				__bg_r	= buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer);
				
				if(__bg_r < 4) break;
				
				__bg_r -= 4;
				__bg_s	= buffer_read(__bg_buffer, buffer_u32);

				if(__bg_r < __bg_s) break;
				
				var __bg_struct		= buffer_read(__bg_buffer, buffer_string);
				
				if(__bg_object == undefined || __bg_object.bg_struct != __bg_struct) __bg_object = new (asset_get_index(__bg_struct))();
				
				var __bg_protobuild = self;
				
				with(__bg_object)
				{
					var 
					__bg_schema		= __bg_protobuild.bg_msg_specs[$ bg_struct],
					__bg_specs		= __bg_schema.bg_specs;
					
					for(var i = __bg_schema.bg_value - 1; i >= 0; --i)
					{ 
						var __bg_spec  = __bg_specs[i];
						//Decode the buffer accordingly to spec
						self[$ __bg_spec.bg_name] = __bg_protobuild.bgDecodeValue(__bg_buffer, __bg_spec.bg_type);
					}
		
					__bg_value = self;
				}
				break;
			case bgAssetSprite: case bgAssetObject: case bgAssetPath: case bgAssetScript:
				__bg_r		= buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer);
				if(__bg_r < 2) break;
				
				__bg_r		-= 2;
				__bg_s		= buffer_read(__bg_buffer, buffer_u16);
				
				if(__bg_r < __bg_s) break;
				
				__bg_buff	= buffer_create(__bg_s, buffer_fixed, 1);
				buffer_copy(__bg_buffer, buffer_tell(__bg_buffer), __bg_s, __bg_buff, 0);
				buffer_seek(__bg_buffer, buffer_seek_relative, __bg_s);
				__bg_value	= asset_get_index(buffer_read(__bg_buff, buffer_text));
				buffer_delete(__bg_buff);
				break;
			case bgText:
				__bg_r	= buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer);
				if(__bg_r < 2) break;
				
				__bg_r -= 2;
				__bg_s	= buffer_read(__bg_buffer, buffer_u16);
				
				if(__bg_r < __bg_s) break;
				
				__bg_buff = buffer_create(__bg_s, buffer_fixed, 1);
				buffer_copy(__bg_buffer, buffer_tell(__bg_buffer), __bg_s, __bg_buff, 0);
				buffer_seek(__bg_buffer, buffer_seek_relative, __bg_s);
				__bg_value	= buffer_read(__bg_buff, buffer_text);
				buffer_delete(__bg_buff);
				break;	
			case bgBuffer:
				__bg_r	= buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer);
				
				if(__bg_r < 4) break;
				
				__bg_r -= 4;
				__bg_s	= buffer_read(__bg_buffer, buffer_u32);
				
				if(__bg_r < __bg_s) break;
				
				__bg_value	= buffer_create(__bg_s, buffer_fixed, 1);
				buffer_copy(__bg_buffer, buffer_tell(__bg_buffer), __bg_s, __bg_value, 0);
				buffer_seek(__bg_buffer, buffer_seek_relative, __bg_s);
				break;
			default:
				if(__bg_spec_type >= (bgText - 1))
				{
					bgDebug("Invalid buffer");
					break;
				}
				__bg_buff = buffer_create(__bg_spec_type, buffer_fixed, 1);
				buffer_copy(__bg_buffer, buffer_tell(__bg_buffer), __bg_spec_type, __bg_buff, 0);
				buffer_seek(__bg_buffer, buffer_seek_relative, __bg_spec_type);
				__bg_value	= buffer_read(__bg_buff, buffer_text);
				buffer_delete(__bg_buff);
		}
		
		return __bg_value;
	}
	
	/// @context								self
	/// @function								bgDecodeToStruct(async_load)
	/// @description							Decodes a buffer containing protobuild packets and passes struct to callbacks. 
	///											Additional keys 'bg_async_id', 'bg_async_ip', 'bg_async_port' containing respective 
	///											async_load will be added. Alternativly you can simply place within a async network event.
	/// @param	{Id.DsMap}			async_load	- A ds_map that contains all keys similar to the async_load with network event.
	/// @return {any}
	static bgDecodeToStruct			= function(__bg_async_load = async_load, __bg_skip_interceptor = false)
	{	
		var
		__bg_read_buffer	= __bg_async_load[? "buffer"],
		__bg_size			= __bg_async_load[? "size"],
		__bg_socket_id		= __bg_async_load[? "id"];
		
		buffer_seek(__bg_read_buffer, buffer_seek_start, 0);
		
		if(__bg_size < 4)
		{
			bgWarn("Packet to small");
			return [];
		}
		
		var 
		__bg_buffer_array	= [],
		__bg_header			= buffer_read(__bg_read_buffer, buffer_u16);
		
		switch(__bg_header)
		{
			case bg_proto_code: break;
			case bgCustomProtocol: _bg_custom_protocol(__bg_async_load); return;
			case bgCustomProtocol + 1: bgSecondaryProtocolRun(__bg_async_load); return;
			default:
				bgWarn("Invalid header", __bg_header);
				buffer_resize(__bg_read_buffer, __bg_size);
			    return __bg_buffer_array;
		}
			
		var __bg_target_size = buffer_read(__bg_read_buffer, buffer_u16);
		
		while(__bg_size - buffer_tell(__bg_read_buffer) >= __bg_target_size)
		{
			var
		    __bg_msg_id				= buffer_read(__bg_read_buffer, buffer_u16),
		    __bg_msg_struct			= _bg_msg_array[__bg_msg_id],
			__bg_packet				= {};
				
		    if(__bg_msg_struct != undefined) 
			{
				var 
		        __bg_callback		= __bg_msg_struct.bg_callback,
		        __bg_specs			= __bg_msg_struct.bg_specs;
					
				__bg_packet			= {
					bg_async_id		: __bg_socket_id,
					bg_async_socket : __bg_async_load[? "socket"],
					bg_async_ip		: __bg_async_load[? "ip"],
					bg_async_port	: __bg_async_load[? "port"]
				}
		            
				for(var i = 0, s	= __bg_msg_struct.bg_value; i < s; ++i) 
				{
		            var 
		            __bg_spec		= __bg_specs[i],
		            __bg_spec_type  = __bg_spec.bg_type,
					__bg_spec_name	= __bg_spec.bg_name;
						
		            if(__bg_spec_type == undefined)
					{
						bgWarn("Spec type is undefined for", __bg_spec_name);
						return __bg_buffer_array;
					}
						
					//Pass in buffer size and offset
					var __bg_value	= bgDecodeValue(__bg_read_buffer, __bg_spec_type, __bg_spec.bg_default);
						
					if(__bg_value != undefined) __bg_packet[$ __bg_spec_name] = __bg_value;
					else {
						bgWarn("Invalid value size for spec", __bg_spec_name, "in", __bg_msg_struct.bg_name, ":", __bg_spec_type);
						return __bg_buffer_array;
					}
		        }
		            
				if(__bg_callback != -1)
				{
					if(script_exists(__bg_callback))
					{
						//bgDebug("Executing script", script_get_name(__bg_callback), "with", __bg_packet);
						if(__bg_skip_interceptor || _bg_callback_interceptor(__bg_callback, __bg_packet)) __bg_callback(__bg_packet);
					}else bgWarn("Callback script", __bg_callback, "within msg", __bg_msg_struct, "doesnt exists");
						
					delete __bg_packet;
				}else array_push(__bg_buffer_array, __bg_packet);
		    }
			else{
				bgWarn("Message", __bg_msg_id,"not in protocol");
				return __bg_buffer_array;
			}
		}
		
		return __bg_buffer_array;
	}
	
	/// @context								self
	/// @function								bgStreamDecodeToStruct(async_load)
	/// @description							Decodes a stream buffer containing protobuild packets and passes struct to callbacks. 
	///											Additional keys 'bg_async_id', 'bg_async_ip', 'bg_async_port' containing respective 
	///											async_load will be added. Alternativly you can simply place within a async network event.
	/// @param	{Id.DsMap}			async_load	- A ds_map that contains all keys similar to the async_load with network event.
	/// @return {any}
	static bgStreamDecodeToStruct	= function(__bg_async_load = async_load, __bg_skip_interceptor = false)
	{
		var
		__bg_src_buffer		= __bg_async_load[? "buffer"],
		__bg_size			= __bg_async_load[? "size"],
		__bg_sender_id		= __bg_async_load[? "id"],
		__bg_id				= -1,
		__bg_buffer_array	= [],
		__bg_read_buffer	= _bg_read_buffers[__bg_sender_id] ?? buffer_create(0, buffer_grow, 1);
		
		buffer_copy(__bg_src_buffer, 0, __bg_size, __bg_read_buffer, buffer_get_size(__bg_read_buffer));
		
		buffer_seek(__bg_read_buffer, buffer_seek_start, 0);
		
		while(buffer_get_size(__bg_read_buffer) - buffer_tell(__bg_read_buffer) > 4)
		{
		    var 
			__bg_offset		= buffer_tell(__bg_read_buffer),
		    __bg_header		= buffer_read(__bg_read_buffer, buffer_u16);
			
			switch(__bg_header)
			{
				case bg_proto_code: break;
				case bgCustomProtocol:
					__bg_size					= buffer_get_size(__bg_read_buffer);
					
					_bg_async_load[? "id"]		= __bg_sender_id;
					_bg_async_load[? "ip"]		= __bg_async_load[? "ip"];
					_bg_async_load[? "port"]	= __bg_async_load[? "port"];
					_bg_async_load[? "buffer"]	= __bg_read_buffer;
					_bg_async_load[? "size"]	= __bg_size;
					
					_bg_custom_protocol(_bg_async_load);
				
					var 
					__bg_tell					= buffer_tell(__bg_read_buffer),
			        __bg_buffer					= buffer_create(__bg_size - __bg_tell, buffer_grow, 1);
		        
					buffer_copy(__bg_read_buffer, __bg_tell, __bg_size - __bg_tell, __bg_buffer, 0);
		        
					buffer_delete(__bg_read_buffer);
		        
					__bg_read_buffer			= __bg_buffer;
					_bg_read_buffers[__bg_sender_id] = __bg_read_buffer;
					continue;
				case bgCustomProtocol + 1: 
					__bg_size					= buffer_get_size(__bg_read_buffer);
					
					_bg_async_load[? "id"]		= __bg_sender_id;
					_bg_async_load[? "ip"]		= __bg_async_load[? "ip"];
					_bg_async_load[? "port"]	= __bg_async_load[? "port"];
					_bg_async_load[? "buffer"]	= __bg_read_buffer;
					_bg_async_load[? "size"]	= __bg_size;
					
					bgSecondaryProtocolRun(_bg_async_load);
				
					var 
					__bg_tell					= buffer_tell(__bg_read_buffer),
					__bg_remaining				= __bg_size - __bg_tell,
				    __bg_buffer					= buffer_create(__bg_remaining, buffer_grow, 1);
					
					buffer_copy(__bg_read_buffer, __bg_tell, __bg_remaining, __bg_buffer, 0);
					buffer_delete(__bg_read_buffer);
		        
					__bg_read_buffer			= __bg_buffer;
					_bg_read_buffers[__bg_sender_id] = __bg_read_buffer;
					continue;
				default:
					bgTrace("Invalid header", __bg_header);
					buffer_resize(__bg_read_buffer, __bg_size);
				    return __bg_buffer_array;
			}
		    
			var 
			__bg_target_size	= buffer_read(__bg_read_buffer, buffer_u16),
			__bg_remaining		= buffer_get_size(__bg_read_buffer) - buffer_tell(__bg_read_buffer);
		    
			if(__bg_remaining >= __bg_target_size)
			{
				if(__bg_remaining < 2) 
				{
					bgWarn("Invalid packet cannot parse msg id");
					return __bg_buffer_array;
				}
				
		        var
		        __bg_msg_id				= buffer_read(__bg_read_buffer, buffer_u16),
				__bg_msg_struct			= _bg_msg_array[__bg_msg_id];
				
		        if(__bg_msg_struct != undefined) 
				{
		            if(__bg_id == -1) __bg_id = __bg_msg_id;
					
					var 
		            __bg_callback		= __bg_msg_struct.bg_callback,
		            __bg_specs			= __bg_msg_struct.bg_specs,
					__bg_packet			= {
						bg_async_id		: __bg_sender_id,
						bg_async_socket : __bg_async_load[? "socket"],
						bg_async_ip		: __bg_async_load[? "ip"],
						bg_async_port	: __bg_async_load[? "port"]
					}
					
		            for(var i = 0, s = __bg_msg_struct.bg_value; i < s; ++i) 
					{
		                var 
		                __bg_spec		= __bg_specs[i],
		                __bg_spec_type  = __bg_spec.bg_type,
						__bg_spec_name	= __bg_spec.bg_name;
		                
						if(__bg_spec_type == undefined)
						{
							bgWarn("Spec type undef for", __bg_spec_name);
							
							var __bg_buffer = _bg_read_buffers[__bg_sender_id];
							
							if(__bg_buffer != undefined)
							{
								buffer_delete(__bg_buffer);
								_bg_read_buffers[__bg_sender_id] = undefined;
							}
							
							return __bg_buffer_array;
						}
						
						var __bg_value = bgDecodeValue(__bg_read_buffer, __bg_spec_type, __bg_spec.bg_default);
						
						if(__bg_value != undefined) __bg_packet[$ __bg_spec_name] = __bg_value;
						else{
							bgWarn("Invalid value size for spec", __bg_spec_name, "in", __bg_msg_struct.bg_name, ":", __bg_spec_type);
								
							var __bg_buffer = _bg_read_buffers[__bg_sender_id];
							
							if(__bg_buffer != undefined)
							{
								buffer_delete(__bg_buffer);
								_bg_read_buffers[__bg_sender_id] = undefined;
							}
							
							return __bg_buffer_array;
						}
		            }
					
		            if(__bg_callback != -1)
					{
						if(script_exists(__bg_callback))
						{
							//bgDebug("Executing script", script_get_name(__bg_callback), "with", __bg_packet);
							if(__bg_skip_interceptor || _bg_callback_interceptor(__bg_callback, __bg_packet)) __bg_callback(__bg_packet);
						}else bgWarn("Callback script", __bg_callback, "within msg", __bg_msg_struct, "doesnt exists");
						
						delete __bg_packet;
					}else array_push(__bg_buffer_array, __bg_packet);
		        }
				else{
					bgWarn("Message", __bg_msg_id,"not in protocol");
					
					var __bg_buffer = _bg_read_buffers[__bg_sender_id];
					
					if(__bg_buffer != undefined)
					{
						buffer_delete(__bg_buffer);
						_bg_read_buffers[__bg_sender_id] = undefined;
					}
					
					return __bg_buffer_array;
				}
				
				__bg_size	= buffer_get_size(__bg_read_buffer);
				
				var 
		        __bg_length = 4 + __bg_target_size,
		        __bg_buffer	= buffer_create(__bg_size - __bg_length, buffer_grow, 1);
		        
				buffer_copy(__bg_read_buffer, __bg_length, __bg_size - __bg_length, __bg_buffer, 0);
		        
				buffer_delete(__bg_read_buffer);
		        
				__bg_read_buffer = __bg_buffer;
				_bg_read_buffers[__bg_sender_id] = __bg_read_buffer;
		    }else{
		        buffer_seek(__bg_read_buffer, buffer_seek_start, __bg_offset);
		        break;
		    }
		}
		
		var __bg_remaining = buffer_get_size(__bg_read_buffer) - buffer_tell(__bg_read_buffer);
		if(__bg_remaining)
		{
			_bg_read_buffers[__bg_sender_id] = __bg_read_buffer;
			if(__bg_id != -1) bgWarn("Trailing", __bg_remaining, "(bytes) detected after read from", _bg_msg_array[__bg_id].bg_name, "onward");
		}
		else {
			var __bg_buffer = _bg_read_buffers[__bg_sender_id];
			if(__bg_buffer != undefined)
			{
				buffer_delete(__bg_buffer);
				_bg_read_buffers[__bg_sender_id] = undefined;
			}
		}
		return __bg_buffer_array;
	}
	
	/// @context								self
	/// @function								bgBuildBuffer(bufferid, msgName, value, ...)
	/// @description							Creates a proto buffer with header, and size included. If no arguments or bufferid == -2 a buffer will be created
	///											If a custom buffer was passed it will return it's id else returns the protobuild interface thus can be chained. 5+ Overload
	///											bgBuildBuffer(bgNewBuffer)
	///											bgBuildBuffer(bgWriteBuffer)
	///											bgBuildBuffer(bufferid)
	///											bgBuildBuffer(msgName)
	///											bgBuildBuffer(bufferid, msgName, ...)
	/// @param	 {Any}				*bufferid	- Buffer index to write to. Can enter bgWriteBuffer to use internal write buffer.
	/// @param   {string}			*msgName	- Name of the message to write to the buffer. Default current message.
	/// @param	 {string}			*...		- additional messages.
	/// @return {Any}
	static bgBuildBuffer			= function()
	{
		var 
		__bg_count	 = argument_count,
		__bg_size	 = 0,
		__bg_msg_name,
		__bg_buff;
		
		switch(__bg_count)
		{
			case 0:
				__bg_buff			= bgNewBuffer;
				__bg_msg_name		= bg_msg_current;
				__bg_size			+= bg_msg_specs[$ __bg_msg_name].bg_size;
				break;
			case 1:
				var __bg_input		= argument[0];
				if(typeof(__bg_input) == "string")
				{
					__bg_buff		= _bg_write_buffer;
					__bg_msg_name	= __bg_input;
				}else{
					__bg_buff		= __bg_input == bgWriteBuffer? _bg_write_buffer: __bg_input;
					__bg_msg_name	= bg_msg_current;
				}
				__bg_size			+= bg_msg_specs[$ __bg_msg_name].bg_size;
				break;
			case 2:
				__bg_buff			= argument[0] == bgWriteBuffer? _bg_write_buffer: argument[0];
				__bg_msg_name		= argument[1] == "" ? bg_msg_current: argument[1];
				__bg_size			+= bg_msg_specs[$ __bg_msg_name].bg_size;
				break;
			default:
				__bg_buff			= argument[0] == bgWriteBuffer? _bg_write_buffer: argument[0];
				for(var i = 1; i < __bg_count; ++i) __bg_size += bg_msg_specs[$ argument[i]].bg_size;
		}
		
		//Must increment size by 2
		if(__bg_buff != bgNewBuffer) buffer_resize(__bg_buff, __bg_size + 6);
		else __bg_buff = buffer_create(__bg_size + 6, buffer_fixed, 1);
		
		buffer_seek(__bg_buff, buffer_seek_start, 0);
		buffer_write(__bg_buff, buffer_u16, bg_proto_code);
		buffer_write(__bg_buff, buffer_u16, __bg_size + 2);
		
		//If the protomessage only contains a msg id simply add it.
		if(__bg_size == 0) buffer_write(__bg_buff, buffer_u16, bg_msg_specs[$ __bg_msg_name].bg_id);
		
		bg_msg_current = __bg_msg_name;
		
		return __bg_buff == _bg_write_buffer? self: __bg_buff;
	}
	
	/// @context								self
	/// @function								bgGetBuffer()
	/// @description							Returns the internal write buffer. for READONLY!!! purposes.
	/// @return {Id.Buffer}						Returns the internal write buffer. for READONLY!!! purposes.
	static bgGetBuffer				= function()
	{
		return _bg_write_buffer;	
	}
	
	/// @context								self
	/// @function								bgBufferExtend(bufferid, msgName)
	/// @description							Increases a buffer, adding more messages to it. Returns the protobuild interface thus can be chained.
	/// @param {Id.Buffer}			bufferid	- Buffer index to write into. Can enter bgWriteBuffer to use internal write buffer.
	/// @param	 {string}			msgName		- Name of the proto message to add.
	/// @param	 {string}			*...		- additional proto messages.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgBufferExtend			= function(__bg_buff)
	{
		if(__bg_buff == bgWriteBuffer) __bg_buff = _bg_write_buffer;
		if(!buffer_exists(__bg_buff))
		{
			bgWarn("Buffer", __bg_buff, "does not exist");
			return self;
		}
		var __bg_size = 0;
		for(var i = 1; i < argument_count; ++i) __bg_size += bg_msg_specs[$ argument[i]].bg_size + 2;
		buffer_resize(__bg_buff, buffer_get_size(__bg_buff) + __bg_size);
		buffer_poke(__bg_buff, 2, buffer_u16, buffer_peek(__bg_buff, 2, buffer_u16) + __bg_size);
		return self;
	}
	
	/// @context								self
	/// @function								bgBufferReset(bufferid)
	/// @description							Resets the buffer to zeros, setting the pointer to just after header/size. Returns the protobuild interface thus can be chained.
	/// @param {Id.Buffer}			*bufferid	- Buffer index to reset. Default: uses internal write buffer.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgBufferReset			= function(__bg_buff = _bg_write_buffer)
	{
		if(!buffer_exists(__bg_buff))
		{
			bgWarn("Buffer", __bg_buff, "does not exist");
			return self;
		}
		buffer_fill(__bg_buff, 4, buffer_u8, 0, buffer_get_size(__bg_buff) - 4);
		buffer_seek(__bg_buff, buffer_seek_start, 4);
		return self;
	}
	
	/// @context								self
	/// @function								bgBufferResize(bufferid, msgName, ...)
	/// @description							Resize a buffer to a new length. Returns the protobuild interface thus can be chained.
	/// @param {Id.Buffer}			bufferid	- Buffer index to write into. Can enter bgWriteBuffer to use internal write buffer.
	/// @param	 {string}			msgName		- Name of the proto message to add.
	/// @param	 {string}			...			- additional proto messages.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgBufferResize			= function(__bg_buff = _bg_write_buffer)
	{
		if(__bg_buff == bgWriteBuffer) __bg_buff = _bg_write_buffer;
		if(!buffer_exists(__bg_buff))
		{
			bgWarn("Buffer", __bg_buff, "does not exist");
			return self;
		}
		var __bg_size = 0;
		for(var i = 0; i < argument_count; ++i) __bg_size += bg_msg_specs[$ argument[i]].bg_size + 2;
		buffer_resize(__bg_buff, __bg_size + 4);
		buffer_seek(__bg_buff, buffer_seek_start, 0);
		buffer_write(__bg_buff, buffer_u16, bg_proto_code);
		buffer_write(__bg_buff, buffer_u16, __bg_size);
		return self;
	}
	
	/// @context								self
	/// @function								bgProtoBuildCleanup()
	/// @description							Cleans up the proto construct. Must create a new one for use.
	static bgProtoBuildCleanup		= function()
	{
		delete bg_msg_specs
		_bg_msg_array = undefined;
		
		buffer_delete(_bg_write_buffer);
		
		ds_map_destroy(_bg_async_load);
		
		bgSecondaryRemoveAll();
		
		_bg_secondary_protocol_array = undefined;
		
		for(var i = 0; i < 65535; ++i) bgBufferIndexClear(i);
	}
	
	/// @context								self
	/// @function								bgBufferResetAll()
	/// @description							Resets all proto buffers. Returns the protobuild interface thus can be chained.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgBufferResetAll			= function()
	{
		buffer_resize(_bg_write_buffer, 1);
		buffer_seek(_bg_write_buffer, buffer_seek_start, 0);
		for(var i = 0; i < 65535; ++i) bgBufferIndexClear(i);
		return self;
	}
	
	/// @context								self
	/// @function								bgBufferIndexClear(index)
	/// @description							Clears a index read buffer. Should be used during server disconnect event within network event, using the client's socket id. Returns the protobuild interface thus can be chained.
	/// @param		{Real}			index		- Index within array to clear.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgBufferIndexClear		= function(__bg_index)
	{
		var b = _bg_read_buffers[__bg_index];
		if(b != undefined)
		{
			buffer_delete(b);
			_bg_read_buffers[__bg_index] = undefined;
		}
		return self;
	}
	
	/// @context								self
	/// @function								bgExport(fname)
	/// @description							Exports current protobuild to a json file. Returns the protobuild interface thus can be chained.
	/// @param	  {string}			fname		- File name to export to.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgExport					= function(__bg_fname)
	{
		var 
		__bg_export_str = json_stringify(bg_specs),
		__bg_buff		= buffer_create(string_byte_length(__bg_export_str), buffer_fixed, 1);
		buffer_write(__bg_buff, buffer_text, __bg_export_str);
		buffer_save(__bg_buff, __bg_fname);
		buffer_delete(__bg_buff);
		return self;
	}
	
	/// @context								self
	/// @function								bgImport(fname)
	/// @description							Imports a proto build to current. Returns false if failed to parse file, or protobuild interface thus can be chained.
	/// @param	  {string}			fname		- File name to import from.
	/// @return {Any}
	static bgImport					= function(__bg_fname)
	{
		var __bg_buff = buffer_load(__bg_fname);
		
		try
		{
			bg_msg_specs = json_parse(buffer_read(__bg_buff, buffer_text));
		}catch(e){
			bgWarn("Failed to import proto build from", __bg_fname, e.message);	
			return false;
		}
		
		for(var i = 0; i < 65535; ++i) _bg_msg_array[i] = undefined;
		
		for(var i = 0, a = variable_struct_get_names(bg_msg_specs), s = array_length(a); i < s; ++i)
		{
			var
			m = bg_msg_specs[$ a[i]],
			c = m.bg_callback_str;
			
			_bg_msg_array[m.bg_id] = m;
			
			if(c != "") m.bg_callback = asset_get_index(c);
			else m.bg_callback = -1;
		}
		buffer_delete(__bg_buff);
		return self;
	}
	
	/// @context								self
	/// @function								bgSetCode(code)
	/// @description							Sets the protobuild code. Warning code should normally NEVER be changed after set. 
	/// @param {Real}				uuid		- A new unique code used to identify protocol, and verify connection, and packets.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSetCode				= function(__bg_code)
	{
		bg_proto_code				= __bg_code;
		return self;
	}
	
	/// @context								self
	/// @function								bgGetCode()
	/// @description							Returns protobuild code.
	/// @return {Real}				
	static bgGetCode				= function()
	{
		return bg_proto_code;	
	}
	
	/// @context								self
	/// @function								bgSetHash()
	/// @description							Creates a sha1_utf8 hash of the protobuild. Returns the protobuild interface thus can be chained.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSetHash				= function(__bg_hash = undefined)
	{
		if(__bg_hash != undefined)
		{
			bg_hash = __bg_hash;
			return self;	
		}
		
		var 
		__bg_specs		= variable_struct_get_names(bg_msg_specs),
		__bg_hash_array = [];
		
		array_sort(__bg_specs, true);
		
		for(var i = array_length(__bg_specs) - 1; i >= 0; --i)
		{
			var __bg_msg	= bg_msg_specs[$ __bg_specs[i]];
			
			array_push(__bg_hash_array, i, __bg_msg.bg_id, __bg_msg.bg_name);
			
			for(var o = __bg_msg.bg_value - 1; o >= 0; --o)
			{
				var __bg_msg_spec = __bg_msg.bg_specs[o];
				array_push(__bg_hash_array, __bg_msg_spec.bg_name, __bg_msg_spec.bg_type, __bg_msg_spec.bg_default);
			}
		}
		
		bg_hash = sha1_string_utf8(json_stringify(__bg_hash_array));
		__bg_hash_array = undefined;
		return self;	
	}
	
	/// @context								self
	/// @function								bgGetHash()
	/// @description							Returns the hash of the protobuild.
	static bgGetHash				= function()
	{
		return bg_hash;
	}
	
	/// @context								self
	/// @function								bgPacketizeCustomStream(target_buffer, async_load, callback)
	/// @description							Packetize custom protocol tcp stream executing callback. Callback must return a boolen on whether 
	///											it has read the necessary data from the buffer. Must update targeted buffer with function return 
	///											buffer to prevent Illegal Buffer index issues due to buffer deletion.
	/// @param {Id.Buffer}			buffer		- Buffer to concatnate too.
	/// @param	{Id.DsMap}			async_load	- A ds_map that contains all keys similar to the async_load with network event.
	/// @param {Function}			callback	- Callback function(buffer, async_load) to execute. Must return a booling whether it has read the data.
	/// @return {ID.Buffer}						Returns target_buffer or a poentially new buffer one.
	static bgPacketizeCustomStream	= function(__bg_target_buffer, __bg_async_load, __bg_callback)
	{
		var 
		__bg_size = __bg_async_load[? "size"],
		__bg_buff = __bg_async_load[? "buffer"];
		
		//Concat async buffer to to auxiliary read buffer due to stream.
		buffer_copy(__bg_buff, 0, __bg_size, __bg_target_buffer, buffer_get_size(__bg_target_buffer));
		
		//Update the read pos.
        buffer_seek(__bg_buff, buffer_seek_start, __bg_size);
		
		buffer_seek(__bg_target_buffer, buffer_seek_start, 0);
		
        while(buffer_get_size(__bg_target_buffer) - buffer_tell(__bg_target_buffer))
		{
            var __bg_offset   = buffer_tell(__bg_target_buffer);
            
			//Skip header
			buffer_read(__bg_target_buffer, buffer_u16);
			
			if(!__bg_callback(__bg_target_buffer, __bg_async_load))
			{
				buffer_seek(__bg_target_buffer, buffer_seek_start, __bg_offset);
				return __bg_target_buffer;
			}
			
			//Delete buffer data.
			var 
            __bg_length = buffer_tell(__bg_target_buffer) - __bg_offset,
            __bg_size	= buffer_get_size(__bg_target_buffer),
            __bg_buffer	= buffer_create(__bg_size - __bg_length, buffer_grow, 1);
            buffer_copy(__bg_target_buffer, __bg_length, __bg_size - __bg_length, __bg_buffer, 0);
            buffer_delete(__bg_target_buffer);
            return __bg_buffer;
        }	
	}
	
	/// @context								self
	/// @function								bgSecondaryProtocolAdd(...functions)
	/// @description							Adds a function(s) to be executed during network async event when proto_code is 65535.
	/// @param {Function}			...function	- Callback function(async_load) to be executed when proto_code is 65535.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSecondaryProtocolAdd	= function()
	{
		for(var i = 0; i < argument_count; ++i)
		{
			var 
			k = argument[i],
			f = false;
		
			for(var o = 0; o < _bg_secondary_protocol_length; ++o)
			{
				if(_bg_secondary_protocol_array[o] == k) 
				{
					f = true;
					break;
				}
			}
		
			if(!f)
			{
				array_push(_bg_secondary_protocol_array, k);
				_bg_secondary_protocol_length++;
			}
		}
		return self;
	}
	
	/// @context								self
	/// @function								bgSecondaryProtocolRemove(...functions)
	/// @description							Remove(s) SecondaryProtocol function.
	/// @param {Function}			...function	- Function to be removed.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSecondaryProtocolRemove= function()
	{
		for(var i = 0; i < argument_count; ++i)
		{
			var k = argument[i];
			for(var o = 0; o < _bg_secondary_protocol_length; ++o)
			{
				if(_bg_secondary_protocol_array[o] == k)
				{
					array_delete(_bg_secondary_protocol_array, o, 1);
					_bg_secondary_protocol_length--;
					break;	
				}
			}
		}
		
		return self;
	}
	
	/// @context								self
	/// @function								bgSecondaryRemoveAll()
	/// @description							Removes all SecondaryProtocol functions.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSecondaryRemoveAll		= function()
	{
		while(_bg_secondary_protocol_length > 0) bgSecondaryProtocolRemove(_bg_secondary_protocol_array[0]);
		return self;
	}
	
	/// @context								self
	/// @function								bgSecondaryProtocolRun(async_load)
	/// @description							Executes all SecondaryProtovol functions passing in the async ds_map.
	/// @param	{Id.DsMap}			async_load	- A ds_map that contains all keys similar to the async_load with network event.
	/// @return {Struct}						Returns the protobuild interface thus can be chained.
	static bgSecondaryProtocolRun	= function(__bg_async_load = async_load)
	{
		for(var i = 0; i < _bg_secondary_protocol_length; ++i) _bg_secondary_protocol_array[i](__bg_async_load);
		return self;
	}
	
	//For compatibility with bgLogger
	if(self[$ "bgLog"] == undefined)
	{
		bgLog	= function(__bg_level, __bg_message)
		{
			if(__bg_level != "FATAL" && __bg_level != "ERROR")
			{
				show_debug_message("["+string(date_get_month(date_current_datetime()))+"/"+string(date_get_day(date_current_datetime()))+" "+string(date_get_hour(date_current_datetime()))+":"+string(date_get_minute(date_current_datetime()))+":"+string(date_get_second(date_current_datetime()))+"]"+" [BG] ["+__bg_level+"] "+__bg_message);
			}else show_error(__bg_message, __bg_level == "FATAL");
		}
		
		bgWarn	= function()
		{
			var r = string(argument[0]);
			for(var i = 1; i < argument_count; ++i) r += " " + string(argument[i]);	
			bgLog("WARN", r);
			return self;
		}
		
		bgFatal = function()
		{
			var r = string(argument[0]);
			for(var i = 1; i < argument_count; ++i) r += " " + string(argument[i]);
			bgLog("ERROR", r);
			return self;
		}
	}
}
