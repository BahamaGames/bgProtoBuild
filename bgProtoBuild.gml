/*
	Special thanks goes to Maseta. Base was made from his protobuild
	https://meseta.itch.io/lockstep
*/
/// @function			bgProtoBuild(UUID, callstackAmount)
/// @description		Builds proto messages / buffers to be used for rpcs.
///						Most methods can be chained to utilize the internal write buffer, and current message feature.
/// @param {real}		uuid A unique code used to identify protocol, and verify connection, and packets.
/// @param {real}		callstackAmount The maximum depth of the callstack that is shown upon error.
/// Feather disable all
function bgProtoBuild(__bg_code = 0xAE1B, __bg_log_callstack = 1) : bgLogger() constructor
{
	/*
	All accessiable variables, and methods are abbrivated with bg
	to avoid conflicts with other projects.
	
	All variables are to be used for READONLY purposes if wishs to write
	simply make a copy, and use that.
	*/
	bg_code						= __bg_code;
	bg_hash						= "";
	bg_msg_specs				= {};
	bg_msg_index				= [];
	bg_msg_current				= "";
	bg_size						= 0;
	_bg_log_callstack			= __bg_log_callstack;
	_bg_write_buffer			= buffer_create(1, buffer_grow, 1);
	_bg_read_buffers 			= array_create(65535, undefined);
	
	/*
	Values from 65518-65530 in respective order are reserved 
	for read and writes. If you have a value within those range 
	use bgText or bgBuffer to convert it. bgtext is capped at a
	65535 length, and bgBuffer 4294967295. Beware of mtu.
	*/
	#macro bgWriteBuffer		_bg_write_buffer
	#macro bgBool				0xFFEE
	#macro bgU8					0xFFEF
	#macro bgS8					0xFFF0
	#macro bgU16				0xFFF1
	#macro bgS16				0xFFF2
	#macro bgF16				0xFFF3
	#macro bgU32				0xFFF4
	#macro bgS32				0xFFF5
	#macro bgF32				0xFFF6
	#macro bgU64				0xFFF7
	#macro bgF64				0xFFF8
	#macro bgText				0xFFF9
	#macro bgBuffer				0xFFFA
	
	/// @function				bgMsgCreate(msgName, callback)
	/// @description			Creates a new proto message with an optional callback. Returns the protobuild interface thus can be chained.
	/// @param   {string}		msgName		Proto message name.
	/// @param   {Function}		*callback	Function of callback handler to trigger when recieving this message.
	static bgMsgCreate			= function(__bg_msg_name, __bg_callback = noone)
	{
		if(argument_count < 1)
		{
			bgWarn("Invalid argument amount");
			return self;
		}
		if(bg_msg_specs[$ __bg_msg_name] == undefined)
		{
			var __bg_msg = {
				bg_id			: bg_size++,
				bg_name			: __bg_msg_name,
				bg_specs		: [],
				bg_types		: [],
				bg_size			: 0,
				bg_value		: 0,
				bg_callback		: __bg_callback,
				bg_callback_str	: __bg_callback != noone? script_get_name(__bg_callback): ""
			}
			array_push(bg_msg_index, __bg_msg);
			bg_msg_specs[$ __bg_msg_name] = __bg_msg;
			bg_msg_current = __bg_msg_name;
			return self;
		}else bgWarn(__bg_msg_name + " was already added");
	}
	
	/// @function				bgMsgSetCurrent(msgName)
	/// @description			Sets the current proto message context. Useful for when chaining. Returns the protobuild interface thus can be chained.
	/// @param   {string}		msgName		Proto message name.
	static bgMsgSetCurrent		= function(__bg_msg_name)
	{
		bg_msg_current = __bg_msg_name;
		return self;
	}
	
	/// @function				bgMsgAddSpec(valName, valType, valDefault)
	/// @description			Adds a spec/value to the current proto message. Returns the protobuild interface thus can be chained.
	/// @param   {string}		valName		Name of the value to be added.
	/// @param	   {real}		valType		Type of value. Can be of any number value greater than 0, but less than bgBuffer.
	/// @param		{any}		valDefault	Default value to be used when encoding from struct.
	static bgMsgAddSpec			= function(__bg_val_name, __bg_val_type, __bg_val_default)
	{
		var __bg_msg = bg_msg_specs[$ bg_msg_current];
		if(__bg_msg == undefined) bgFatal(bg_msg_current,"does not exist");
		else{
			var __bg_specs = __bg_msg.bg_specs;
			
			for(var i = 0, s = __bg_msg.bg_value; i < s; i++)
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
				case bgText:
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
					if(__bg_val_type >= bgBuffer + 1)
					{
						bgFatal("Attempting to add a value greater than or equal to", bgBuffer + 1,"within message", bg_msg_current, "at", __bg_val_name);
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
	
	/// @function				bgMsgUpdateCallback(msgName, callback)
	/// @description			Updates the callback of a pre existing proto message, also sets the current message. Returns the protobuild interface thus can be chained.
	/// @param	  {string}		msgName		Proto message name.
	/// @param    {Function}	callback	Function handler to trigger when recieving the proto message.
	static bgMsgUpdateCallback	= function(__bg_msg_name, __bg_callback)
	{
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		if(__bg_msg == undefined){
			bgFatal(__bg_msg_name, "does not exist");
			return self;
		}
		__bg_msg.bg_callback     = __bg_callback;
		__bg_msg.bg_callback_str = script_get_name(__bg_callback);
		_bg_msg_current			 = __bg_msg_name;
		return self	
	}
	
	/// @function				bgMsgGet(msgName)
	/// @description			Returns a previously created proto message.
	/// @param	  {string}		msgName		Proto message name. Default: current proto message would be used.
	/// @return   {Struct}		Returns the proto message specs.
	static bgMsgGet				= function(__bg_msg_name = bg_msg_current)
	{
		return bg_msg_specs[$ __bg_msg_name]
	}
	
	/// @function				bgMsgSetSize(msgName, size)
	/// @description			Sets a message's size. Usefull for previously unknown message sizes. +1 Overload
	///							.bgMsgSetSize(msgName, size),
	///							.bgMsgSetSize(size). Returns the protobuild interface thus can be chained.
	/// @param    {string}		*msgName	- Proto message name. Default: current proto message would be used.
	/// @param	    {real}		new_size	- Size to assign to message.
	static bgMsgSetSize			= function(__bg_msg_name, __bg_size)
	{
		if(argument_count == 1)
		{
			__bg_size		= __bg_msg_name;
			__bg_msg_name	= bg_msg_current;
		}
		var 
		__bg_msg = bg_msg_specs[$ __bg_msg_name],
		__bg_arr = __bg_msg.bg_types;
		for(var i = 0, s = array_length(__bg_arr); i < s; i++)
		{
			var __bg_spec_type = __bg_arr[i];
		    switch(__bg_spec_type) 
			{
		        case bgBool:
		        case bgU8:
		        case bgS8:
		            __bg_size += 1;
		            break;
				case bgText:
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
					if(__bg_spec_type >= bgBuffer + 1)
					{
						bgFatal("Attempting to add a value greater than or equal to", bgBuffer + 1,"within message", __bg_msg_name);
						return self;
					}
					__bg_size += __bg_spec_type;
		    }
		}
		__bg_msg.bg_size	= __bg_size;
		bg_msg_current		= __bg_msg_name;
		return self;
	}
	
	/// @function				bgMsgGetSize(msgName)
	/// @description			Gets the size of a pre existing proto message.
	/// @param    {string}		*msgName	- Proto message name. Default: current message would be used.
	/// @return     {real}		Returns the size of the message.
	static bgMsgGetSize			= function(__bg_msg_name = bg_msg_current)
	{
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		if(__bg_msg == undefined)
		{
			bgFatal("message", __bg_msg_name, "not found");
			return -1;
		}
		return __bg_msg.bg_size + 2;
	}
	
	/// @function				bgMsgGetAll()
	/// @description			Returns all proto messages cached.
	/// @return	  {Struct}
	static bgMsgGetAll			= function()
	{
		return bg_msg_specs;
	}
	
	/// @function				bgEncodeValue(bufferid, bgType, value(s))
	/// @description			Encodes a buffer using proto message. Returns the protobuild interface thus can be chained.
	/// @param	{Id.Buffer}		bufferid	Buffer index to write to.
	/// @param {Constant.bgType} bgType		Type of bgBuffer to convert to gml buffer_*.
	/// @param		 {any}		value(s)	Sequential value(s) to write to buffer.
	static bgEncodeValue		= function(__bg_buff, __bg_type, __bg_insert_val)
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
			case bgText:
				var __bg_leng = string_length(__bg_insert_val);
				buffer_write(__bg_buff, buffer_u16, __bg_leng);
				buffer_write(__bg_buff, buffer_text, __bg_insert_val);
				break;
			case bgBuffer:
				var __bg_size = buffer_get_size(__bg_insert_val);
		        buffer_write(__bg_buff, buffer_u32, __bg_size);
		        var __bg_tell = buffer_tell(__bg_buff);
				buffer_copy(__bg_insert_val, 0, __bg_size, __bg_buff, __bg_tell);
				buffer_seek(__bg_buff, buffer_seek_start, __bg_tell + __bg_size);
				break;
			default:
				var __bg_tell = buffer_tell(__bg_buff);
				buffer_fill(__bg_buff, __bg_tell, buffer_u8, 0, __bg_type);
				buffer_write(__bg_buff, buffer_text, string_copy(__bg_insert_val, 1, __bg_type));
				buffer_seek(__bg_buff, buffer_seek_start, __bg_tell + __bg_type);
		}
		return self;
	}
	
	/// @function				bgEncodeDirect(bufferid, msgName, value)
	/// @description			Encodes a buffer using data from arguments. MUST provide all values. Will return false if an issue was detected, else protobuild interface thus can be chained.
	/// @param	{Id.Buffer}		bufferid	Buffer index to write to. Can enter noone to use built in write buffer.
	/// @param	  {string}		msgName		Name of the proto message. Can enter "" to use the current message.
	/// @param		   {any}	value(s)	Sequential value(s) in message spec.
	static bgEncodeDirect		= function(__bg_buffer, __bg_msg_name, __bg_values)
	{
		if(argument_count < 2) bgFatal("Invalid amount of arguments");
		if(__bg_msg_name = "") __bg_msg_name = bg_msg_current;
		
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		
		if(__bg_msg == undefined){
			bgWarn("message", __bg_msg_name, "not found");
			return false;
		}
		
		if(__bg_buffer == noone) __bg_buffer = _bg_write_buffer;
		
		var __bg_types = __bg_msg.bg_types;
		
		buffer_write(__bg_buffer, buffer_u16, __bg_msg.bg_id);
		
		for(var i = 0, s = __bg_msg.bg_value; i < s && i + 2 < argument_count; i++) bgEncodeValue(__bg_buffer, __bg_types[i], argument[i + 2]);
		
		return self;
	}
	
	/// @function				bgEncodeFromStruct(bufferid, msgName, struct)
	/// @description			Encodes a buffer using data from struct. If key is missing default value will be used. Returns the protobuild interface thus can be chained.
	/// @param	{Id.Buffer}		bufferid	Buffer index to write to. Can enter noone to use built in write buffer.
	/// @param	  {string}		msgName		Name of the proto message. Can enter "" to use the current message.
	/// @param	  {Struct}		value		A struct containing the message key and desired value.
	static bgEncodeFromStruct	= function(__bg_buff, __bg_msg_name, __bg_struct)
	{
		if(__bg_buff == noone) __bg_buff		= _bg_write_buffer;
		if(__bg_msg_name == "") __bg_msg_name	= bg_msg_current;
		
		var __bg_msg = bg_msg_specs[$ __bg_msg_name];
		
		if(__bg_msg == undefined)
		{
			bgWarn("message", __bg_msg_name, "not found");
			return false;	
		}
		
		var __bg_specs = __bg_msg.bg_specs;
		
		buffer_write(__bg_buff, buffer_u16, __bg_msg.bg_id);
		
		for(var i = 0, s = __bg_msg.bg_value; i < s; i++)
		{
			var 
			__bg_spec		= __bg_specs[i],
			__bg_insert_val = __bg_struct[$ __bg_spec.bg_name];
			if(__bg_insert_val == undefined) __bg_insert_val = __bg_spec.bg_default;
			
			bgEncodeValue(__bg_buff, __bg_spec.bg_type, __bg_insert_val);
		}
		return self;
	}
	
	/// @function				bgDecodeValue(bufferid, specType)
	/// @description			Decodes a protospec into a buffer, returning the value.
	/// @param	{Id.Buffer}		bufferid	- Buffer index to decode.
	/// @param {Constant.bgType} bgType		- Type of buffer to decode a real value between 1 and bgBuffer.
	/// @return {any}
	static bgDecodeValue		= function(__bg_buffer, __bg_spec_type)
	{
		var __bg_value = undefined;
		switch(__bg_spec_type)
		{
			case bgBool: case bgU8:
				__bg_value	= buffer_read(__bg_buffer, buffer_u8);
				break;
			case bgS8:
				__bg_value	= buffer_read(__bg_buffer, buffer_s8);
				break;
			case bgU16:
				__bg_value	= buffer_read(__bg_buffer, buffer_u16);
				break;
			case bgS16:
				__bg_value	= buffer_read(__bg_buffer, buffer_s16);
				break;
			case bgF16:
				__bg_value	= buffer_read(__bg_buffer, buffer_f16);
				break;
			case bgU32:
				__bg_value	= buffer_read(__bg_buffer, buffer_u32);
				break;
			case bgS32:
				__bg_value	= buffer_read(__bg_buffer, buffer_s32);
				break;
			case bgF32:
				__bg_value	= buffer_read(__bg_buffer, buffer_f32);
				break;
			case bgU64:
				__bg_value	= buffer_read(__bg_buffer, buffer_u64);
				break;
			case bgF64:
				__bg_value	= buffer_read(__bg_buffer, buffer_f64);
				break;
			case bgText:
				var __bg_r	= buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer);
				if(__bg_r < 2)
				{
					__bg_value = undefined;
					break;
				}
				__bg_r -= 2;
				var __bg_s	= buffer_read(__bg_buffer, buffer_u16);
				if(__bg_r < __bg_s)
				{
					__bg_value = undefined;
					break;
				}
				if(__bg_s > 0)
				{
					var
					__bg_buff	= buffer_create(__bg_s, buffer_u8, 1),
					__bg_tell	= buffer_tell(__bg_buffer);
					buffer_copy(__bg_buffer, __bg_tell, __bg_s, __bg_buff, 0);
					buffer_seek(__bg_buffer, buffer_seek_start, __bg_tell + __bg_s);
					__bg_value	= buffer_read(__bg_buff, buffer_text);
					buffer_delete(__bg_buff);
				}else __bg_value = "";
				break;	
			case bgBuffer:
				var __bg_r	= buffer_get_size(__bg_buffer) - buffer_tell(__bg_buffer);
				if(__bg_r < 4)
				{
					__bg_value = undefined;
					break;
				}
				__bg_r -= 4;
				var __bg_s	= buffer_read(__bg_buffer, buffer_u32);
				if(__bg_r < __bg_s)
				{
					__bg_value = undefined;
					break;
				}
				var 
				__bg_value	= buffer_create(__bg_s, buffer_fixed, 1),
				__bg_tell	= buffer_tell(__bg_buffer);
				buffer_copy(__bg_buffer, __bg_tell, __bg_s, __bg_value, 0);
				buffer_seek(__bg_buffer, buffer_seek_start, __bg_tell + __bg_spec_type);
				break;
			default:
				var 
				__bg_buff	= buffer_create(__bg_spec_type, buffer_u8, 1),
				__bg_tell	= buffer_tell(__bg_buffer);
				buffer_copy(__bg_buffer, __bg_tell, __bg_spec_type, __bg_buff, 0);
				buffer_seek(__bg_buffer, buffer_seek_start, __bg_tell + __bg_spec_type);
				__bg_value	= buffer_read(__bg_buff, buffer_text);
				buffer_delete(__bg_buff);
		}
		return __bg_value;
	}
	
	/// @function				bgDecodeToStruct(bufferid, size, socketid)
	/// @description			Decodes a buffer containing protobuild packets and passes struct to callbacks, or return array. 
	/// @param	{Id.DsMap}		async_load	- A ds_map that contains all keys similar to the async_load with network event. 
	static bgDecodeToStruct		= function(__bg_async_load)
	{	
		var
		__bg_read_buffer	= __bg_async_load[? "buffer"],
		__bg_size			= __bg_async_load[? "size"],
		__bg_socket_id		= __bg_async_load[? "id"];
		if(__bg_size < 4){
			bgWarn("Invalid packet to small");
			return [];	
		}
		buffer_seek(__bg_read_buffer, buffer_seek_start, 0);
		var __bg_buffer_array = [];
		while(buffer_tell(__bg_read_buffer) < __bg_size)
		{
		    var __bg_header = buffer_read(__bg_read_buffer, buffer_u16);
			if(__bg_header != bg_code) 
			{
		        bgWarn("Invalid header", __bg_header);
				buffer_resize(__bg_read_buffer, __bg_size);
		        return __bg_buffer_array;
		    }
		    
			var 
			__bg_target_size = buffer_read(__bg_read_buffer, buffer_u16),
			__bg_tell		 = buffer_tell(__bg_read_buffer);
		    
			while(buffer_tell(__bg_read_buffer) - __bg_tell < __bg_target_size)
			{
		        var
		        __bg_msg_id				= buffer_read(__bg_read_buffer, buffer_u16),
		        __bg_msg_struct			= bg_msg_index[__bg_msg_id],
				__bg_send_struct		= {};
		        if(__bg_msg_struct != undefined) 
				{
					var 
		            __bg_callback		= __bg_msg_struct.bg_callback,
		            __bg_specs			= __bg_msg_struct.bg_specs;
		            for(var i = 0, s	= __bg_msg_struct.bg_value; i < s; i++) 
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
						var __bg_value	= bgDecodeValue(__bg_read_buffer, __bg_spec_type);
						if(__bg_value != undefined) __bg_send_struct[$ __bg_spec_name] = __bg_value;
						else{
							bgWarn("Invalid value size for spec",__bg_spec_name, "in", __bg_msg_id);
							return __bg_buffer_array;
						}
		            }
					__bg_send_struct.bg_async_id	= __bg_socket_id;
					__bg_send_struct.bg_async_ip	= __bg_async_load[? "ip"];
					__bg_send_struct.bg_async_port	= __bg_async_load[? "port"];
		            if(__bg_callback != noone)
					{
						if(script_exists(__bg_callback)) script_execute(__bg_callback, __bg_send_struct);
						else bgWarn("Callback script", __bg_callback, "within msg", __bg_msg_struct, "doesnt exists");
						delete __bg_send_struct;
					}else array_push(__bg_buffer_array, __bg_send_struct);
		        }else{
					bgWarn("Message", __bg_msg_id,"not in protocol");
					return __bg_buffer_array;
				}
		    }
		}
		return __bg_buffer_array;
	}
	
	/// @function				bgStreamDecodeToStruct(bufferid, size, async_load)
	/// @description			Decodes a stream buffer containing protobuild packets and passes struct to callbacks. 
	///							An additional key 'bg_socket_id' containing async_load[? "id"] will be added.
	///							Alternativly you can simply place within a async network event.
	/// @param	{Id.DsMap}		async_load	- A ds_map that contains all keys similar to the async_load with network event. 
	static bgStreamDecodeToStruct = function(__bg_async_load)
	{
		var
		__bg_src_buffer		= __bg_async_load[? "buffer"],
		__bg_size			= __bg_async_load[? "size"],
		__bg_sender_id		= __bg_async_load[? "id"],
		__bg_id				= -1,
		__bg_buffer_array	= [],
		__bg_read_buffer	= _bg_read_buffers[__bg_sender_id];
		
		if(__bg_read_buffer == undefined) __bg_read_buffer = __bg_src_buffer;
		else buffer_copy(__bg_src_buffer, 0, __bg_size, __bg_read_buffer, buffer_get_size(__bg_read_buffer));
		
		buffer_seek(__bg_read_buffer, buffer_seek_start, 0);
		
		while(buffer_get_size(__bg_read_buffer) - buffer_tell(__bg_read_buffer) > 4)
		{
		    var 
			__bg_offset = buffer_tell(__bg_read_buffer),
		    __bg_header = buffer_read(__bg_read_buffer, buffer_u16);
			if(__bg_header != bg_code) {
		        bgWarn("Invalid header", __bg_header);
				buffer_resize(__bg_read_buffer, __bg_size);
		        return __bg_buffer_array;
		    }
		    
			var __bg_target_size = buffer_read(__bg_read_buffer, buffer_u16);
		    
			if(buffer_get_size(__bg_read_buffer) - buffer_tell(__bg_read_buffer) >= __bg_target_size)
			{
		        var
		        __bg_msg_id				= buffer_read(__bg_read_buffer, buffer_u16),
		        __bg_msg_struct			= bg_msg_index[__bg_msg_id],
				__bg_send_struct		= {};
		        if(__bg_msg_struct != undefined) {
		            if(__bg_id == -1) __bg_id = __bg_msg_id;
					var 
		            __bg_callback		= __bg_msg_struct.bg_callback,
		            __bg_specs			= __bg_msg_struct.bg_specs;
		            for(var i = 0, s = __bg_msg_struct.bg_value; i < s; i++) 
					{
		                var 
		                __bg_spec		= __bg_specs[i],
		                __bg_spec_type  = __bg_spec.bg_type,
						__bg_spec_name	= __bg_spec.bg_name;
		                if(__bg_spec_type == undefined){
							bgWarn("Spec type undef for", __bg_spec_name);
							var __bg_buffer = _bg_read_buffers[__bg_sender_id];
							if(__bg_buffer != undefined){
								buffer_delete(__bg_buffer);
								_bg_read_buffers[__bg_sender_id] = undefined;
							}
							return __bg_buffer_array;
						}
						var __bg_value	= bgDecodeValue(__bg_read_buffer, __bg_spec_type);
						if(__bg_value != undefined) __bg_send_struct[$ __bg_spec_name] = __bg_value;
						else{
							bgWarn("Invalid value size for spec",__bg_spec_name, "in", __bg_msg_id);
							var __bg_buffer = _bg_read_buffers[__bg_sender_id];
							if(__bg_buffer != undefined){
								buffer_delete(__bg_buffer);
								_bg_read_buffers[__bg_sender_id] = undefined;
							}
							return __bg_buffer_array;
						}
		            }
		            __bg_send_struct.bg_async_id	= __bg_sender_id;
					__bg_send_struct.bg_async_ip	= __bg_async_load[? "ip"];
					__bg_send_struct.bg_async_port	= __bg_async_load[? "port"];
		            if(__bg_callback != noone){
						if(script_exists(__bg_callback)) script_execute(__bg_callback, __bg_send_struct);
						else bgWarn("Callback script", __bg_callback, "within msg", __bg_msg_struct, "doesnt exists");
						delete __bg_send_struct;
					}else array_push(__bg_buffer_array, __bg_send_struct);
		        }else{
					bgWarn("Message", __bg_msg_id,"not in protocol");
					var __bg_buffer = _bg_read_buffers[__bg_sender_id];
					if(__bg_buffer != undefined){
						buffer_delete(__bg_buffer);
						_bg_read_buffers[__bg_sender_id] = undefined;
					}
					return __bg_buffer_array;
				}
				if(buffer_get_size(__bg_read_buffer) - buffer_tell(__bg_read_buffer))
				{
					__bg_size	= buffer_get_size(__bg_read_buffer);
					var 
		            __bg_length = 4 + __bg_target_size,
		            __bg_buffer	= buffer_create(__bg_size - __bg_length, buffer_grow, 1);
		            buffer_copy(__bg_read_buffer, __bg_length, __bg_size - __bg_length, __bg_buffer, 0);
		            buffer_delete(__bg_read_buffer);
		            __bg_read_buffer = __bg_buffer;
					_bg_read_buffers[__bg_sender_id] = __bg_read_buffer;
				}
		    }else{
		        buffer_seek(__bg_read_buffer, buffer_seek_start, __bg_offset);
		        break;
		    }
		}
		var __bg_remaining = buffer_get_size(__bg_read_buffer) - buffer_tell(__bg_read_buffer);
		if(__bg_remaining){
			_bg_read_buffers[__bg_sender_id] = __bg_read_buffer;
			if(__bg_id != -1) bgWarn("Trailing", __bg_remaining, "(bytes) detected after read from", bg_msg_index[__bg_id].bg_name, "onward");
		}else{
			var __bg_buffer = _bg_read_buffers[__bg_sender_id];
			if(__bg_buffer != undefined){
				buffer_delete(__bg_buffer);
				_bg_read_buffers[__bg_sender_id] = undefined;
			}
		}
		return __bg_buffer_array;
	}
	
	/// @function				bgBufferBuild(bufferid, msgName, value, ...)
	/// @description			Creates a proto buffer with header, and size included. Returns the protobuild interface thus can be chained. 2+ Overload
	///							bgBufferBuild()
	///							bgBufferBuild(bufferid)
	///							bgBufferBuild(msgName)
	///							bgBufferBuild(bufferid, msgName)
	/// @param {Id.Buffer}		*bufferid	- Buffer index to write to. Can enter noone to use internal write buffer.
	/// @param   {string}		*msgName	- Name of the message to write to the buffer. Default current message.
	/// @param	 {string}		*...		- additional messages.
	static bgBufferBuild		= function()
	{
		var 
		__bg_count	 = argument_count,
		__bg_size	 = 0,
		__bg_msg_name,
		__bg_buff;
		switch(__bg_count)
		{
			case 0:
				__bg_buff		= noone;
				__bg_msg_name	= bg_msg_current;
				__bg_size += bgMsgGetSize(__bg_msg_name);
				break;
			case 1:
				var __bg_input	= argument[0];
				if(typeof(__bg_input) == "string"){
					__bg_buff		= _bg_write_buffer;
					__bg_msg_name	= __bg_input;
				}else{
					__bg_buff		= __bg_input;
					__bg_msg_name	= bg_msg_current;
				}
				__bg_size += bgMsgGetSize(__bg_msg_name);
				break;
			case 2:
				__bg_buff		= argument[0];
				__bg_msg_name	= argument[1] == "" ? bg_msg_current: argument[1];
				__bg_size += bgMsgGetSize(__bg_msg_name);
				break;
			default:
				__bg_buff		= argument[0];
				for(var i = 1; i < __bg_count; i++) __bg_size += bgMsgGetSize(argument[i]);		
		}
		if(__bg_buff != _bg_write_buffer) buffer_resize(__bg_buff, __bg_size + 4);
		else if(__bg_buff == noone) __bg_buff = buffer_create(__bg_size + 4, buffer_fixed, 1);
		buffer_seek(__bg_buff, buffer_seek_start, 0);
		buffer_write(__bg_buff, buffer_u16, bg_code);
		buffer_write(__bg_buff, buffer_u16, __bg_size);
		bg_msg_current = __bg_msg_name;
		return __bg_buff == _bg_write_buffer? self: __bg_buff;
	}
	
	/// @function				bgBufferGet()
	/// @description			Returns the internal write buffer. for READONLY!!! purposes.
	static bgBufferGet			= function()
	{
		return _bg_write_buffer;	
	}
	
	/// @function				bgBufferExtend(bufferid, msgName)
	/// @description			Increases a buffer, adding more messages to it. Returns the protobuild interface thus can be chained.
	/// @param {Id.Buffer}		*bufferid	- Buffer index to write into. Can enter noone to use internal write buffer.
	/// @param	 {string}		msgName	- Name of the proto message to add.
	/// @param	 {string}		*...		- additional proto messages.
	static bgBufferExtend		= function(__bg_buff = noone, __bg_msg_name)
	{
		if(__bg_buff == noone) __bg_buff = _bg_write_buffer;
		if(!buffer_exists(__bg_buff))
		{
			bgWarn("Buffer", __bg_buff, "does not exist");
			return self;
		}
		var __bg_size = 0;
		for(var i = 1; i < argument_count; i++) __bg_size += bgMsgGetSize(argument[i]);
		buffer_resize(__bg_buff, buffer_get_size(__bg_buff) + __bg_size);
		buffer_poke(__bg_buff, 2, buffer_u16, buffer_peek(__bg_buff, 2, buffer_u16) + __bg_size);
		return self;
	}
	
	/// @function				bgBufferReset(bufferid)
	/// @description			Resets the buffer to zeros, setting the pointer to just after header/size. Returns the protobuild interface thus can be chained.
	/// @param {Id.Buffer}		*bufferid	- Buffer index to reset. Default: uses internal write buffer.
	static bgBufferReset		= function(__bg_buff = _bg_write_buffer)
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
	
	/// @function				bgBufferResize(bufferid, msgName, ...)
	/// @description			Resize a buffer to a new length. Returns the protobuild interface thus can be chained.
	/// @param {Id.Buffer}		bufferid	- Buffer index to write into. Can enter noone to use internal write buffer.
	/// @param	 {string}		msgName	- Name of the proto message to add.
	/// @param	 {string}		...			- additional proto messages.
	static bgBufferResize		= function(__bg_buff = noone, __bg_msg_name)
	{
		if(__bg_buff == noone) __bg_buff = _bg_write_buffer;
		if(!buffer_exists(__bg_buff))
		{
			bgWarn("Buffer", __bg_buff, "does not exist");
			return self;
		}
		var __bg_size = 0;
		for(var i = 0; i < argument_count; i++) __bg_size += bgMsgGetSize(argument[i]);
		buffer_resize(__bg_buff, __bg_size + 4);
		buffer_seek(__bg_buff, buffer_seek_start, 0);
		buffer_write(__bg_buff, buffer_u16, bg_code);
		buffer_write(__bg_buff, buffer_u16, __bg_size);
		return self;
	}
	
	/// @function				bgProtoBuildCleanup()
	/// @description			Cleans up the proto construct. Must create a new one for use.
	static bgProtoBuildCleanup	= function()
	{
		delete bg_msg_specs
		bg_msg_index = undefined;
		buffer_delete(_bg_write_buffer);
		for(var i = 0; i < 65535; i++) bgBufferIndexClear(i);
	}
	
	/// @function				bgBufferResetAll()
	/// @description			Resets all proto buffers. Returns the protobuild interface thus can be chained.
	static bgBufferResetAll		= function(){
		buffer_resize(_bg_write_buffer, 1);
		buffer_seek(_bg_write_buffer, buffer_seek_start, 0);
		for(var i = 0; i < 65535; i++) bgBufferIndexClear(i);
		return self;
	}
	
	/// @function				bgBufferIndexClear(index)
	/// @description			Clears a index read buffer. Should be used during server disconnect event within network event, using the client's socket id. Returns the protobuild interface thus can be chained.
	/// @param		{real}		index	- Index within array to clear.
	static bgBufferIndexClear	= function(__bg_index){
		var b = _bg_read_buffers[__bg_index];
		if(b != undefined){
			buffer_delete(b);
			_bg_read_buffers[__bg_index] = undefined;
		}
		return self;
	}
	
	/// @function				bgExport(fname)
	/// @description			Exports current protobuild to a json file. Returns the protobuild interface thus can be chained.
	/// @param	  {string}		fname		- File name to export to.
	static bgExport				= function(__bg_fname)
	{
		var 
		__bg_export_str = json_stringify(bg_specs),
		__bg_buff		= buffer_create(string_byte_length(__bg_export_str), buffer_fixed, 1);
		buffer_write(__bg_buff, buffer_text, __bg_export_str);
		buffer_save(__bg_buff, __bg_fname);
		buffer_delete(__bg_buff);
		return self;
	}
	
	/// @function				bgImport(fname)
	/// @description			Imports a proto build to current. Returns false if failed to parse file, or protobuild interface thus can be chained.
	/// @param	  {string}		fname		- File name to import from.
	static bgImport				= function(__bg_fname)
	{
		var __bg_buff = buffer_load(__bg_fname),
		try
		{
			bg_msg_specs = json_parse(buffer_read(__bg_buff, buffer_text));
		}catch(e){
			bgWarn("Failed to import proto build from", __bg_fname);	
			return false;
		}
		
		bg_msg_index = [];
		
		for(var i = 0, a = variable_struct_get_names(bg_msg_specs), s = array_length(a); i < s; i++)
		{
			var 
			k = a[i],
			m = bg_msg_specs[$ k],
			c = m.bg_callback_str;
			bg_msg_index[m.bg_id] = m;
			
			if(c != "") m.bg_callback = asset_get_index(bg_callback_str);
			else m.bg_callback = noone;
		}
		buffer_delete(__bg_buff);
		return self;
	}
	
	/// @function				bgHashSet()
	/// @description			Creates a sha1_utf8 hash of the protobuild. Returns the protobuild interface thus can be chained.
	static bgHashSet			= function()
	{
		var __bg_hash_array = [];
		for(var i = 0; i < bg_size; i++)
		{
			var __bg_msg = bg_msg_index[i];
			array_push(__bg_hash_array, i, __bg_msg.bg_id, __bg_msg.bg_name);
			for(var o = 0, s = __bg_msg.bg_value; o < s; o++)
			{
				var __bg_msg_spec = __bg_msg.bg_specs[o];
				array_push(__bg_hash_array, __bg_msg_spec.bg_name, __bg_msg_spec.bg_type, __bg_msg_spec.bg_default);
			}
		}
		bg_hash = sha1_string_utf8(json_stringify(__bg_hash_array));
		__bg_hash_array = undefined;
		return self;	
	}
	
	/// @function				bgHashGet()
	/// @description			Returns the hash of the protobuild.
	static bgHashGet			= function()
	{
		return bg_hash;
	}

	//For compatibility with bgLogger
	if(!variable_instance_exists(self, "bgLog"))
	{
		bgLog	= function(__bg_level, __bg_message)
		{
			var 
			__bg_timestamp = "["+string(date_get_month(date_current_datetime()))+"/"+string(date_get_day(date_current_datetime()))+" "+string(date_get_hour(date_current_datetime()))+":"+string(date_get_minute(date_current_datetime()))+":"+string(date_get_second(date_current_datetime()))+"]",
			__bg_callstack = _bg_log_callstack;
		
			if(__bg_callstack) __bg_message += "\n[LOCATION]: "+string(debug_get_callstack(__bg_callstack));
		
			if(__bg_level != "FATAL" && __bg_level != "ERROR"){
				if(_bg_log_callstack) show_debug_message(__bg_timestamp+" [BG] ["+__bg_level+"] "+__bg_message);
			}else show_error(__bg_message, __bg_level == "FATAL");
		}
		bgWarn	= function()
		{
			var r = string(argument[0]);
			for(var i = 1; i < argument_count; i++) r += " " + string(argument[i]);	
			bgLog("WARN", r);
			return self;
		}
		bgFatal = function()
		{
			var r = string(argument[0]);
			for(var i = 1; i < argument_count; i++) r += " " + string(argument[i]);
			bgLog("ERROR", r);
			return self;
		}
	}
}
