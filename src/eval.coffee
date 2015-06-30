# Description:
#   In-chat JavaScript evaluation and REPL shell mode. Useful for
#   debugging live Hubot instance or hot fixing. The Robot object
#   is accesible within the context of the evaluation which means 
#   that all the internals of Hubot can be accessed and modified.
#   
# Dependencies:
#   "hubot-auth": ~"1.2.0"
#
# Configuration:
#   HUBOT_EVAL_ROLES - A comma separate list of roles allowed  
#                      to evaluate JavaScript code in-chat.
#
# Commands:
#   hubot eval javascript - Executes js code and returns result
#   hubot start shell - Enters shell mode for sender in current room
#   hubot exit shell - Exits shell mode for sender in current room
#
# Author:
#   Stoyan Dimkov <stoyan.dimkov@gmail.com>
#


{inspect} = require 'util'


# Configure eval-allowed roles
roles = ['admin']
if process.env.HUBOT_EVAL_ROLES 
  newRoles = process.env.HUBOT_EVAL_ROLES.split ','
  roles.push role for role in newRoles when role not in roles


module.exports = (robot) ->


  # Redirect console.log() to caller's chat room
  evalRoom = ''
  console = log: (obj) ->
    robot.messageRoom evalRoom, obj.toString()
    return undefined


  # Private: evaluate javascript code snippet (String)
  # 
  # code - A String containing valid JavaScript snippet
  # 
  # Returns parsed and formatted results from execution
  evaluate = (code) ->
    try
      return '-> ' + inspect eval(code
        .replace('‘', "'").replace('’', "'")
        .replace('“', '"').replace('”', '"'))
    catch err
      robot.logger.error 'Error during eval: ' + err
      return err.toString()


  # Private: authorizes user calls for evaluation
  # 
  # res - A Response object for evaluation call
  # 
  # Returns true when authorized and false when not
  auth = (res) ->
    user = res.envelope.user
    for role in roles
      return true if robot.auth.hasRole user, role
    res.reply "Sorry! You're not allowed to do code evaluation."
    return false


  # Public: Wrap robot#receive to handle shell commands before listeners. If the
  # message is not a shell command it handles it to the original robot#receive.
  #  * Performs better than hear all approach
  #  * Guarantees no listener will accidently match your shell code statements
  #  * Doesn't break robot#catchAll
  #
  # message - A Message instance. Listeners can flag this message as 'done' to
  #           prevent further execution.
  #
  # Returns nothing.
  receiveRaw = robot.receive.bind robot
  robot.receive = (message) ->
    if message.user.shell and message.user.shell[message.room] and message.text
      res = new robot.Response robot, message
      if message.text.trim().toLowerCase() == 'exit shell'
        delete message.user.shell[message.room]
        res.reply 'Exited interactive shell'
      else
        evalRoom = message.room
        res.send evaluate message.text
    else
      receiveRaw message


  # Add a listener that evals JS on demmand and returns result
  #  * Requires admin or user specified eval role
  robot.respond /eval (.+)/i, (res) ->
    if auth res
      evalRoom = res.envelope.room
      res.send evaluate res.match[1]


  # Add a listener that starts interactive shell mode for the sender in
  # the current room. Multiple shells can be running in multiple rooms.
  #  * Requires admin or user specified eval role
  robot.respond /start shell/i, (res) ->
    if auth res
      res.envelope.user.shell ||= {}
      res.envelope.user.shell[res.envelope.room] = true
      res.reply 'Entered interactive shell mode!\nType "exit shell" to exit'



  # Alternative implementaiton that uses hear all matcher and doesn't wrap
  # robot#receive function. Has the following drawback - all messages get 
  # caught so robot#catchAll effectively stops working
  #
  # robot.hear /(.+)/, (res) ->
  #   if res.envelope.user.shell? and res.envelope.user.shell[res.envelope.room]
  #     if res.match.input.trim() == 'stop shell'
  #       delete res.envelope.user.shell[res.envelope.room]
  #       res.reply 'Exited interactive shell'
  #     else
  #       evalRoom = res.envelope.room
  #       res.send evaluate res.match.input