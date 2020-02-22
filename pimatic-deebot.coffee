module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  _ = require('lodash')
  M = env.matcher
  deebot = require('ecovacs-deebot')
  #sucks = require('./..') # ./node_modules/pimatic-deebot/node-modules/ecovacs-deebot/index.js')
  nodeMachineId = require('node-machine-id')

  class DeebotPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-deebot-config-schema'

      @deviceConfigDef = require("./device-config-schema")

      @email = @config.email # "email@domain.com";
      @password = @config.password #"a1b2c3d4";
      @countrycode = @config.countrycode # 'DE';

      EcoVacsAPI = deebot.EcoVacsAPI
      VacBot = deebot.VacBot

      @email = @config.email # "email@domain.com";
      password = @config.password #"a1b2c3d4";
      countrycode = @config.countrycode # 'DE';

      @password_hash = EcoVacsAPI.md5(password)
      device_id = EcoVacsAPI.md5(nodeMachineId.machineIdSync())
      countries = deebot.countries
      @continent = countries[countrycode].continent.toLowerCase()
      @api = new EcoVacsAPI(device_id, countrycode, @continent)

      @framework.deviceManager.registerDeviceClass('DeebotDevice', {
        configDef: @deviceConfigDef.DeebotDevice,
        createCallback: (config, lastState) => new DeebotDevice(config, lastState, @, @api, EcoVacsAPI, @continent)
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
              _did = (if vacuum.did? then vacuum.did else vacuum)
              if _.find(@framework.deviceManager.devicesConfig,(d)=> d.id is _did)
                env.logger.info "Device '" + _did + "' already in config"
              else
                config =
                  id: (if vacuum.did? then vacuum.did else vacuum).toLowerCase()
                  name: (if vacuum.name? then vacuum.name else vacuum).toLowerCase()
                  class: "DeebotDevice"
                  nickname: (if vacuum.nick? then vacuum.nick else "")
                @framework.deviceManager.discoveredDevice( "Deebot", config.name, config)
          )
        ).catch((e) =>
          env.logger.error 'Failure in connecting: ' +  e.message
        )
      )


  class DeebotDevice extends env.devices.Device

    constructor: (config, lastState, @plugin, api, EcoVacsAPI, continent) ->
      @config = config
      @id = @config.id
      @name = @config.name

      @api = api
      @EcoVacsAPI_REALM = EcoVacsAPI.REALM
      @vacuum = @id
      @continent = continent
      VacBot = deebot.VacBot

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

      for _attr in vacBotListeners
        do (_attr) =>
          @attributes[_attr] =
            description: _attr
            type: "string"
            label: _attr
            acronym: _attr
            hidden: @show
            displaySparkline: false
          @attributeValues[_attr] = (if lastState?[_attr]?.value? then lastState[_attr].value else "")
          @_createGetter(_attr, =>
            return Promise.resolve @attributeValues[_attr]
          )
          @setAttr _attr, @attributeValues[_attr]
      if @attributes?.BatteryInfo?
        #  @attributes.BatteryInfo.type = "number"
        @attributes?.BatteryInfo.unit = "%"
      if @attributes?.WaterLevel?
        #  @attributes.WaterLevel.type = "number"
        @attributes.WaterLevel.unit = "%"

      for _attr in @config.attributes
        do (_attr) =>
          @attributes[_attr].hidden = @hide

      initDeebot = () =>
        @api.connect(@plugin.email, @plugin.password_hash)
        .then(() =>
          @setAttr("status","connecting")
          @api.devices()
          .then((devices) =>
            #device = _.find(devices, (d)=> d.name is @vacuum)
            device = devices[0]
            if device?
              @vacbot = new VacBot(@api.uid, @EcoVacsAPI_REALM, @api.resource, @api.user_access_token, device, @continent)
              @vacbot.on 'ready', (event) =>
                env.logger.debug('connected')
                @setAttr("status","Deebot offline")

                for listener in vacBotListeners
                  do(listener)=>
                    @vacbot.on(listener, (value) =>
                      unless value?
                        return
                      @attributeValues[listener] = value
                      @emit listener, value
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
                    @vacbot.run("GetWaterLevel")
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
          @reconnectTimer = setTimeout(initDeebot, 600000)
          env.logger.info "Beebot is offline, try reconnecting in 10 minutes"
          @setAttr("status","offline")
        )


      initDeebot()


      # MQTT
      #@vacbot.on('message', (event) =>
      #  env.logger.debug('[app2.js] message: ' + event)
      #)


      ###
      console.log('[app2.js] isKnownDevice: ' + @vacbot.isKnownDevice());
      console.log('[app2.js] isSupportedDevice: ' + @vacbot.isSupportedDevice());
      console.log('[app2.js] name: ' + @vacbot.getDeviceProperty('name'));
      console.log('[app2.js] hasMainBrush: ' + @vacbot.hasMainBrush());
      console.log('[app2.js] hasSpotAreas: ' + @vacbot.hasSpotAreas());
      console.log('[app2.js] hasCustomAreas: ' + @vacbot.hasCustomAreas());
      console.log('[app2.js] hasMoppingSystem: ' + @vacbot.hasMoppingSystem());
      console.log('[app2.js] hasVoiceReports: ' + @vacbot.hasVoiceReports());

      if (!@vacbot.useMqtt)
        @vacbot.run('Clean');
        @vacbot.run('GetLifeSpan', 'main_brush')
        @vacbot.run('GetLifeSpan', 'side_brush')
        @vacbot.run('GetLifeSpan', 'filter')
        interval = setInterval(() =>
          @vacbot.run('GetCleanState')
          @vacbot.run('GetChargeState')
          @vacbot.run('GetBatteryState')
        , 60000)

      vacbot.run("Clean", mode, action);
        mode: auto, edge, spot, spot_area, single_room, stop
        action: start, pause, resume, stop
      vacbot.run("SpotArea", mode, action, area);
        comma-separated list of numbers starting by 0 (e.g. 1,3) for areas to be cleaned.
      vacbot.run("CustomArea", mode, action, map_position, cleanings);
        map_position comma-separated list of exactly 4 position values for x1,y1,x2,y2
          (e.g. -3975.000000,2280.000000,-1930.000000,4575.000000)
          position 0.000000,0.000000,0.000000,0.000000 the position of the charging station
        cleanings: 1,2
      vacbot.run("Edge");
      vacbot.run("Spot");
      vacbot.run("Stop");
      vacbot.run("Pause");
      vacbot.run("Charge");
      vacbot.run("GetCleanState");
      vacbot.run("GetChargeState");
      vacbot.run("GetBatteryState");
      vacbot.run("PlaySound");
      vacbot.run('GetLifeSpan', 'main_brush');
      vacbot.run('GetLifeSpan', 'side_brush');
      vacbot.run('GetLifeSpan', 'filter');
      vacbot.run('GetWaterLevel');
      vacbot.run('SetWaterLevel', level);
      ###

      super()

    execute: (command) =>
      return new Promise((resolve,reject) =>

        env.logger.debug "Commando ontvangen " + command
        switch command
          when "clean"
            @vacbot.run("Clean") #, @capabilities.currentMode, "start")
          when "pause"
            @vacbot.run("Pause") #, @capabilities.currentMode, "pause")
          when "resume"
            @vacbot.run("Resume") #, @capabilities.currentMode, "resume")
          when "stop"
            @vacbot.run("Stop") #, @capabilities.currentMode, "stop")
          when "charge"
            @vacbot.run("Charge")
          else
            env.logger.debug "Unknown command " + command + "-" + action
            reject()
        resolve()
      )


    setAttr: (attr, _status) =>
      unless @attributeValues[attr] is _status
        @attributeValues[attr] = _status
        @emit attr, @attributeValues[attr]
        env.logger.debug "Set attribute '#{attr}' to '#{_status}'"


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
      deebotDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "DeebotDevice"
      ).value()

      setCommand = (command) =>
        @command = command

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
          )
        ])

      match = m.getFullMatch()
      if match? #m.hadMatch()
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new DeebotActionHandler(@framework, beebotDevice, @command)
        }
      else
        return null


  class DeebotActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @beebotDevice, @command) ->

    executeAction: (simulate) =>
      if simulate
        return __("would have cleaned \"%s\"", "")
      else
        @beebotDevice.execute(@command)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "")
        )


  deebotPlugin = new DeebotPlugin
  return deebotPlugin
