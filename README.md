# pimatic-deebot
Pimatic plugin to control one or more Ecovacs Deebot cleaning robots

Before install this plugin on linux based systems the following commandline commands should be executed (a reboot might be necessary after the first line):
```
sudo apt-get update
sudo apt-get install build-essential libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev
sudo npm install canvas --unsafe-perm=true
```
These libs are needed for creating map functionality and to identify the spot area during cleaning.

The plugin can be installed via the plugins page of Pimatic.

## Config of the plugin
```
{
  email:        "The email address for your Deebots account"
  password:     "The password for your Deebots account"
  countrycode:  "Your country code like 'DE'
  debug:        "Debug mode. Writes debug messages to the Pimatic log, if set to true."
}
```

## Config of a Deebot Device

Devices are added via the discovery function. Per cleaning robot a DeebotDevice is discovered unless the device is already in the config.
The automatic generated Id must not change. Its the unique reference to your vacuum. You can change the Pimatic device name after you have saved the device.

```
{
  nickname:
    "A nickname for the Deebot set via the app and then used in Pimatic
  show:       
    "If 'all': variables will be shown in the GUI except the variables selected in Attributes.
    If 'none': nothing will be shown in the GUI, except the ones selected in Attributes."
  attributes:
    "Deebot attributes that will be hidden (show=all) or shown (show=none) in the GUI."
  items:[
    "ChargeState", "FanSpeed", "CleanReport", "BatteryInfo",
    "LifeSpan_filter" , "LifeSpan_main_brush",
    "LifeSpan_side_brush", "WaterLevel", "WaterBoxInfo"
  ]
}
```

The attributes are updated and visible in the Gui. The items you can use depend on your type of Deebot.
The Deebot can be controlled via rules

The action syntax:
```
  deebot <Pimatic Deebot Id>
    [clean] [<room-number>|$rooms-variable]
    [cleanarea] [x1,y1,x2,y2]|$area-variable cleanings 1..2|$cleanings-variable
    [pause|resume|stop|charge|
    [speed] <speed-number>|$speed-variable
```

The \<room-nummer> or the \$roomsvariable are optional. If you leave them out, the vacuum will start the default routine. The \$rooms-variable is variable with room-numbers separated by a comma. Example:  0,1,8,3,2
The fan speed-number must be 1 (silient), 2 (normal), 3 (high) or 4 (very high)

## Support of models
**Supported models**
- Deebot Slim 2
- Deebot 601
- Deebot 710/711
- Deebot 900/901
- Deebot Ozmo 610
- Deebot Ozmo 920
- Deebot Ozmo 930
- Deebot Ozmo 950

**Theses models are known to work**
- Deebot Ozmo 900

**These models should work**
- Deebot N79T
- Deebot M88
- Deebot 600/605

---
This plugin is based on the ecovacs-deebot library from [mrbungle64](https://github.com/mrbungle64/ecovacs-deebot.js).

The minimum node requirement for this plugin is node v8!
