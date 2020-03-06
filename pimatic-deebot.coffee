module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  M = env.matcher
  _ = require('lodash')
  deebot = require('ecovacs-deebot')
  nodeMachineId = require('node-machine-id')

  class DeebotPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-deebot-config-schema'

      @deviceConfigDef = require("./device-config-schema")

      @email = @config.email # "email@domain.com";
      @password = @config.password #"a1b2c3d4";
      @countrycode = @config.countrycode # 'DE';

      EcoVacsAPI = deebot.EcoVacsAPI

      @email = @config.email # "email@domain.com";
      password = @config.password #"a1b2c3d4";
      countrycode = (@config.countrycode ).toUpperCase() # 'DE';

      @password_hash = EcoVacsAPI.md5(password)
      device_id = EcoVacsAPI.md5(nodeMachineId.machineIdSync())
      countries = deebot.countries
      @continent = countries[countrycode].continent.toLowerCase()
      @api = new EcoVacsAPI(device_id, countrycode, @continent)

      @framework.deviceManager.registerDeviceClass('DeebotDevice', {
        configDef: @deviceConfigDef.DeebotDevice,
        createCallback: (config, lastState) => new DeebotDevice(config, lastState, @, @framework, @api, EcoVacsAPI, @continent)
      })

      @framework.ruleManager.addActionProvider(new DeebotActionProvider(@framework))

      @framework.deviceManager.on('discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-deebot', 'Searching for new devices'

        ### vacuum data
        "did": "E0000962817609920075",
        "name": "E0000962817609920075",
        "class": "113",
        "resource": "atom",
        "nick": null,
        "company": "eco-legacy"
        ###

        @api.connect(@email, @password_hash)
        .then(() =>
          @api.devices()
          .then((devices) =>
            for vacuum in devices
              _did = (if vacuum.did? then vacuum.did else vacuum).toLowerCase()
              if _.find(@framework.deviceManager.devicesConfig,(d) => (d.id).indexOf(_did)>=0)
                env.logger.info "Device '" + _did + "' already in config"
              else
                config =
                  id: _did
                  name: (if vacuum.nick? then vacuum.nick else if vacuum.name? then vacuum.name else vacuum).toLowerCase()
                  class: "DeebotDevice"
                  nickname: (if vacuum.nick? then vacuum.nick else "")
                @framework.deviceManager.discoveredDevice( "Deebot", config.name, config)
          )
        ).catch((e) =>
          env.logger.error 'Failure in connecting: ' +  e.message
        )
      )


  class DeebotDevice extends env.devices.Device

    constructor: (config, lastState, @plugin, @framework, api, EcoVacsAPI, continent) ->
      @config = config
      @id = @config.id
      @name = @config.name

      @api = api
      @EcoVacsAPI_REALM = EcoVacsAPI.REALM
      @vacuum = @id
      @continent = continent

      @waterLevels = ["min","normal","high","max"]

      @capabilities =
        hasMainBrush: false
        hasSpotAreas: false
        hasCustomAreas: false
        hasMoppingSystem: false
        hasVoiceReports: false
        modes : ["auto", "edge", "spot", "spot_area", "single_room", "stop"]
        currentMode: "auto"
        SpotArea: []
        CustomArea:
          map_position:
            x1: 0
            y1: 0
            x2: 0
            y2: 0
          cleanings: 1

      @attributes = {}
      @attributeValues = {}

      vacBotListeners = @plugin.deviceConfigDef.DeebotDevice.properties.attributes.items.enum

      @show = @hide = false
      if not @config.show? or @config.show is "all"
        @show = false
        @hide = true
      else
        @show = true
        @hide = false

      @attributes["status"] =
        description: "status"
        type: "string"
        label: "status"
        acronym: "status"
        displaySparkline: false
      @attributeValues["status"] = "offline"
      @_createGetter("status", =>
        return Promise.resolve @attributeValues["status"]
      )
      @setAttr "status", @attributeValues["status"]
      @numberAttributes = ["BatteryInfo","LifeSpan_filter","LifeSpan_main_brush","LifeSpan_side_brush"]
      @booleanAttributes = ["WaterBoxInfo"]

      for _attr in vacBotListeners
        do (_attr) =>
          @attributes[_attr] =
            description: _attr
            type: "string"
            label: _attr
            acronym: _attr
            hidden: @show
            displaySparkline: false
          if _.find(@numberAttributes, (n)=> n.indexOf(_attr)>=0)
            @attributes[_attr].type = "number"
            @attributes[_attr].unit = "%"
            @attributes[_attr].displayFormat = "fixed,decimal:0"
            _lastState = (if lastState?[_attr]?.value? then Number lastState[_attr].value else 0 )
          else if _.find(@booleanAttributes, (n)=> n.indexOf(_attr)>=0)
            @attributes[_attr].type = "boolean"
            _lastState = (if lastState?[_attr]?.value? then lastState[_attr].value else false )
          else  
            _lastState = (if lastState?[_attr]?.value? then lastState[_attr].value else "" )
          @attributeValues[_attr] = _lastState
          @_createGetter(_attr, =>
            return Promise.resolve @attributeValues[_attr]
          )

      @framework.on 'after init', =>
        for _attr in @config.attributes
          do (_attr) =>
            @attributes[_attr].hidden = @hide
            @setAttr _attr, @attributeValues[_attr]

      initDeebot = () =>
        @api.connect(@plugin.email, @plugin.password_hash)
        .then(() =>
          @setAttr("status","connecting")
          @api.devices()
          .then((devices) =>
            #device = _.find(devices, (d)=> d.name is @vacuum)
            device = devices[0]
            if device?
              @vacbot = @api.getVacBot(@api.uid, @EcoVacsAPI_REALM, @api.resource, @api.user_access_token, device, @continent)
              @vacbot.on 'ready', (event) =>
                env.logger.debug('connected')
                @setAttr("status","Deebot connected")

                for listener in vacBotListeners
                  do(listener)=>
                    @vacbot.on(listener, (value) =>
                      unless value?
                        return
                      if listener.indexOf("WaterLevel")>= 0
                        if level<0 then level = 0
                        if level>3 then level = 3
                        @setAttr(listener, @waterLevels[level] )
                      else if (@attributes[listener].type).indexOf("number") >= 0
                        @setAttr(listener, Math.round(Number value))
                      else
                        @setAttr(listener, value)
                      @setAttr("status","Deebot online")
                    )
                @vacbot.on 'error', (err) =>
                  env.logger.error "Error vacbot.on " + err

                getStatus = () =>
                  @vacbot.run("GetBatteryState")
                  @vacbot.run('GetChargeState')
                  @vacbot.run("GetCleanState")
                  if @capabilities.hasMainBrush
                    @vacbot.run('GetLifeSpan', 'main_brush')
                    @vacbot.run('GetLifeSpan', 'side_brush')
                    @vacbot.run('GetLifeSpan', 'filter')
                  if @capabilities.hasMoppingSystem
                    @vacbot.run("GetWaterInfo")
                  @capabilities.hasMainBrush = @vacbot.hasMainBrush()
                  @capabilities.hasSpotAreas = @vacbot.hasSpotAreas()
                  @capabilities.hasCustomAreas = @vacbot.hasCustomAreas()
                  @capabilities.hasMoppingSystem = @vacbot.hasMoppingSystem()
                  @capabilities.hasVoiceReports = @vacbot.hasVoiceReports()
                  @statusTimer = setTimeout(getStatus, 60000)

                getStatus()

              @vacbot.on 'message', (m) =>
                env.logger.debug "Message " + m
              @vacbot.connect_and_wait_until_ready()

          ).catch((err)=>
            env.logger.error "Error getting devices " + err
          )
        ).catch((err) =>
          env.logger.error "Error connecting " + err
          @reconnectTimer = setTimeout(initDeebot, 120000)
          clearTimeout(@statusTimer)
          env.logger.info "Beebot is offline, try reconnecting in 2 minutes"
          @setAttr("status","offline")
        )

      initDeebot()

      super()

    execute: (command, rooms, speed, water, area, cleanings) =>
      return new Promise((resolve,reject) =>
        env.logger.info "Command " + command + ", Rooms " + rooms + ", Speed " + speed + ", area " + JSON.stringify(area) + ", cleanings " + cleanings
        #return
        switch command
          when "clean"
            @vacbot.run("Clean") #, @capabilities.currentMode, "start")
          when "cleanroom"
            @vacbot.run("SpotArea", "start", rooms)
          when "pause"
            @vacbot.run("Pause") #, @capabilities.currentMode, "pause")
          when "resume"
            @vacbot.run("Resume") #, @capabilities.currentMode, "resume")
          when "stop"
            @vacbot.run("Stop") #, @capabilities.currentMode, "stop")
          when "charge"
            @vacbot.run("Charge")
          when "spot"
            @vacbot.run("SpotArea", @capabilities.currentMode, area)
          when "cleanarea"
            @vacbot.run("CustomArea", @capabilities.currentMode, "Clean", area, cleanings)
          when "speed"
            @vacbot.run("SetCleanSpeed", speed)
          when "waterlevel"
            @vacbot.run("SetWaterLevel", water)
          else
            env.logger.debug "Unknown command " + command
            reject()
        resolve()
      )


    setAttr: (attr, _status) =>
      unless @attributeValues[attr] is _status
        env.logger.debug "attribute '" + attr + "' with type '" + @attributes[attr].type + "', is set to " + _status
        @attributeValues[attr] = _status
        @emit attr, _status


    destroy:() =>
      try
        @vacbot.disconnect()
      catch e
        env.logger.debug('Failure in disconnecting: ' + e.message)
      clearTimeout(@reconnectTimer)
      clearTimeout(@statusTimer)

      super()

  class DeebotActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

    parseAction: (input, context) =>

      beebotDevice = null
      @speed = 2
      @waterlevel = 1
      @roomsArray = []
      @roomsStringVar = null
      @waterStringVar = null
      @area = 
        x1: 0
        y1: 0
        x2: 0
        y2: 0
      @areaStringVar = null
      @cleanings = 1
      @cleaningsStringVar = null

      deebotDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "DeebotDevice"
      ).value()

      setCommand = (command) =>
        @command = command

      addSpeed = (m,tokens) =>
        unless tokens>0 and tokens<5
          context?.addError("Speed must be 1, 2, 3 or 4.")
          return
        setCommand("speed")
        @speed = Number tokens


      addRoom = (m,tokens) =>
        unless tokens >=0
          context?.addError("Roomnumber should 0 or higher.")
          return
        @roomsArray.push Number tokens
        setCommand("cleanroom")

      addWaterlevel = (m,tokens) =>
        unless tokens>0 and tokens<5
          context?.addError("Waterlevel must be 1, 2, 3 or 4.")
          return
        setCommand("waterlevel")
        @waterlevel = Number tokens

      roomString = (m,tokens) =>
        unless tokens?
          context?.addError("No variable")
          return
        @roomsStringVar = tokens
        setCommand("cleanroom")
        return

      speedString = (m,tokens) =>
        unless tokens?
          context?.addError("No variable")
          return
        @speedStringVar = tokens
        setCommand("speed")
        return

      waterlevelString = (m,tokens) =>
        unless tokens?
          context?.addError("No variable")
          return
        @waterStringVar = tokens
        setCommand("waterlevel")
        return

      addAreaX1 = (m,tokens) =>
        @area.x1 = tokens
        setCommand("cleanarea")
      addAreaY1 = (m,tokens) =>
        @area.y1 = tokens
        setCommand("cleanarea")
      addAreaX2 = (m,tokens) =>
        @area.x2 = tokens
        setCommand("cleanarea")
      addAreaY2 = (m,tokens) =>
        @area.y2 = tokens
        setCommand("cleanarea")

      areaString = (m,tokens) =>
        unless tokens?
          context?.addError("No variable")
          return
        @areaStringVar = tokens
        setCommand("cleanroom")
        return

      addCleanings = (m,tokens) =>
        env.logger.info "Cleanings " + tokens
        unless (Number tokens) == 1 or (Number tokens) == 2
          context?.addError("Cleanings should be 1 or 2.")
          return
        @cleanings = tokens
        setCommand("cleanarea")

      cleaningsString = (m,tokens) =>
        unless tokens?
          context?.addError("No variable")
          return
        @cleaningsStringVar = tokens
        setCommand("cleanarea")
        return


      m = M(input, context)
        .match('deebot ')
        .matchDevice(deebotDevices, (m, d) ->
          # Already had a match with another device?
          if beebotDevice? and deebotDevices.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          beebotDevice = d
        )
        .or([
          ((m) =>
            return m.match(' clean', (m) =>
              setCommand('clean')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' clean')
              .or([
                ((m) =>
                  return m.match(' [')
                    .matchNumber(addRoom)
                    .match(']')
                ),
                ((m) =>
                  return m.match(' ')
                    .matchVariable(roomString)
                )
              ])
          ),
          ((m) =>
            return m.match(' cleanarea ')
              .or([
                ((m) =>
                  return m.match('[')
                    .matchNumber(addAreaX1)
                    .match(",")
                    .matchNumber(addAreaY1)
                    .match(",")
                    .matchNumber(addAreaX2)
                    .match(",")
                    .matchNumber(addAreaY2)
                    .match(']')
                ),
                ((m) =>
                  return m.matchVariable(areaString)
                )
              ])
              .match(' cleanings ')
                .or([
                  ((m) =>
                    return m.matchNumber(addCleanings)
                  ),
                  ((m) =>
                    return m.matchVariable(cleaningsString)
                  )
                ])
          ),
          ((m) =>
            return m.match(' pause', (m) =>
              setCommand('pause')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' resume', (m) =>
              setCommand('resume')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' stop', (m) =>
              setCommand('stop')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' charge', (m)=>
              setCommand('charge')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' speed ')
              .or([
                ((m) =>
                  return m.matchNumber(addSpeed)
                ),
                ((m) =>
                  return m.matchVariable(speedString)
                )
              ])
          ),
          ((m) =>
            return m.match(' waterlevel ')
              .or([
                ((m) =>
                  return m.matchNumber(addWaterlevel)
                ),
                ((m) =>
                  return m.matchVariable(waterlevelString)
                )
              ])
          )
        ])

      #@rooms = @roomsArray
      #convert rooms array into comma seperated string (list)
      @rooms = ""
      for room,i in @roomsArray
        @rooms += room
        if i < @roomsArray.length - 1
          @rooms += ", "
      #@rooms += ")"
      #env.logger.debug "command " + @command + ", Roomlist " + @rooms

      match = m.getFullMatch()
      if match? #m.hadMatch()
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new DeebotActionHandler(@framework, beebotDevice, @command, @rooms, @roomsStringVar, @speed,  
            @speedStringVar, @waterlevel, @waterStringVar, @area, @areaStringVar, @cleanings, @cleaningsStringVar)
        }
      else
        return null


  class DeebotActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @beebotDevice, @command, @rooms, @roomsStringVar, @speed, 
      @speedStringVar, @waterlevel, @waterStringVar, @area, @areaStringVar, @cleanings, @cleaningsStringVar) ->

    executeAction: (simulate) =>
      if simulate
        return __("would have cleaned \"%s\"", "")
      else
        if @roomsStringVar?
          _var = @roomsStringVar.slice(1) if @roomsStringVar.indexOf('$') >= 0
          _rooms = @framework.variableManager.getVariableValue(_var)
          unless _rooms?
            return __("\"%s\" Rule not executed, #{_rooms} is not a valid room string", "")
          _roomArr = (String _rooms).split(',')
          newRooms = ""
          for room,i in _roomArr
            _room = (room.trimLeft()).trimEnd()
            if Number.isNaN(Number _room) or Number _room < 0 or not (room?) or room is ""
              return __("\"%s\" Rule not executed, #{_rooms} is not a valid room string", "")
            if i > 0 then newRooms = newRooms + " "
            newRooms = newRooms + _room
            if i < (_roomArr.length - 1) then newRooms = newRooms + ","
        else
          newRooms = @rooms

        if @speedStringVar?
          _var = @speedStringVar.slice(1) if @speedStringVar.indexOf('$') >= 0
          _speed = @framework.variableManager.getVariableValue(_var)
          unless _speed?
            return __("\"%s\" Rule not executed, #{_speed} is not a valid variable", "")
          if Number.isNaN(Number _speed) or Number _speed < 1 or Number _speed > 4
            return __("\"%s\" Rule not executed, #{_speed} is not a valid speed value", "")
          newSpeed = _speed
        else
          newSpeed = @speed

        if @waterStringVar?
          _var = @waterStringVar.slice(1) if @waterStringVar.indexOf('$') >= 0
          _waterlevel = @framework.variableManager.getVariableValue(_var)
          unless _waterlevel?
            return __("\"%s\" Rule not executed, #{_waterlevel} is not a valid variable", "")
          if Number.isNaN(Number _waterlevel) or Number _waterlevel < 1 or Number _waterlevel > 4
            return __("\"%s\" Rule not executed, #{_waterlevel} is not a valid waterlevel value", "")
          newWaterlevel = _waterlevel
        else
          newWaterlevel = @waterlevel

        if @areaStringVar?
          _var = @areaStringVar.slice(1) if @areaStringVar.indexOf('$') >= 0
          _area = @framework.variableManager.getVariableValue(_var)
          unless _area?
            return __("\"%s\" Rule not executed, #{_area} is not a valid area string", "")
          _coordsArr = (String _area).split(',')
          newArea = ""
          for coord,i in _coordsArr
            _coord = (coord.trimLeft()).trimEnd()
            if Number.isNaN(Number _coord)
              return __("\"%s\" Rule not executed, #{_coord} is not a valid coordinate number", "")
            if i > 0 then newArea = newArea + " "
            newArea = newArea + _coord
            if i < (_coordsArr.length - 1) then newArea = newArea + ","
        else
          newArea = @area.x1 + ", " + @area.y1 + ", " + @area.x2 + ", " + @area.y2

        if @cleaningsStringVar?
          _var = @cleaningsStringVar.slice(1) if @cleaningsStringVar.indexOf('$') >= 0
          _cleanings = @framework.variableManager.getVariableValue(_var)
          unless _cleanings?
            return __("\"%s\" Rule not executed, #{_cleanings} does not excist", "")
          if Number.isNaN(Number _cleanings) or Number _cleanings < 1 or Number _cleanings > 2
            return __("\"%s\" Rule not executed, #{_cleanings} is not a valid cleanings value", "")
          newCleanings = _cleanings
        else
          newCleanings = @cleanings

        @beebotDevice.execute(@command, newRooms, newSpeed, newWaterlevel, newArea, newCleanings)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "")
        )


  deebotPlugin = new DeebotPlugin
  return deebotPlugin
