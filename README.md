# bgProtoBuild
This is an implementation of protocol buffers that can be used to construct binary messages. This was heavily inspired by Meseta's Protobuild system: https://meseta.itch.io/lockstep.
This interface can also be used as an internal for other related 'bg' interfaces.

### Defining a packet
First we must create an instance, optionally but suggested assigning a uuid.
```
var pb = new bgProtoBuild({code: 1234});
```
Next we can create a message and optionally assign a callback function.
```
pb.bgMsgCreate("player_input", function(data){
  show_debug_message(data);
});
```
The first argument is the message name, and the second optional is the callback that would be called.

Now we can assign values to the message. We can utilize the inheritance chaining. 
```
pb
.bgMsgAddSpec("left", bgBool, false)
.bgMsgAddSpec("right", bgBool, false)
.bgMsgAddSpec("up", bgBool, false)
.bgMsgAddSpec("down", bgBool, false)
.bgMsgAddSpec("mouseX", bgS32, 0)
.bgMsgAddSpec("mouseY", bgS32, 0)
```
Last used message is used when add values thus we dont need to set it. First argument is the spec name, second being a maacro in comparison to ```buffer_``` data types, and last argument is the default value to assign.

### Encoding a packet
Once a message is created, a packet can be constructed using it's definition.
```
//Get inputs
var inputs = {
  left: false,
  right: true,
  down: false
}

var buff = pb
          //Build the "player_inputs" message
          .bgBuildBuffer("player_inputs")
          //Encode it with inputs struct. Since im missing "up" within the inputs struct it will default to false.
          .bgEncodeFromStruct(bgWriteBuffer, "", inputs)
          //Get the internal write buffer for use.
          .bgGetBuffer()
network_send_raw(socket, buff, buffer_get_size(buff));
```

### Decoding a packet
Once a buffer is obtained with a protocol message we can decode it triggering the callback that was assigned to the message or returning an array of structs.
For example within the network event ```network_type_data``` we can simply:
```
var results = pb.bgDecodeToStruct(async_load)
```
The above we simply passed in the network async_load. Since we assigned a callback we'll get this response within the terminal:
```
{left: 0, right: 1, up: 0, down: 0, bg_socket_id: 1}
```
If we had not assigned one, results would contain:
```
[{left: 0, right: 1, up: 0, down: 0, bg_socket_id: 1}]
```
# Cleanup
When done make to sure clean up to prevent memory leak.
```
log.bgProtoBuildCleanup();
delete pb;
```
