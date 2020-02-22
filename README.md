# pimatic-deebot
Pimatic plugin to control one or more Ecovacs Deebot cleaning robots

## Config of the plugin
```
{
  email:        "The email address for your Deebots account"
  password:     "The password for your Deebots account"
  countrycode:  "Your country code like 'DE'"
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
  deebot <Pimatic Deebot Id> [clean|pause|resume|stop|charge]
```

---
The plugin is node v4-v10 compatible and in development.

You could backup Pimatic before you are using this plugin!
