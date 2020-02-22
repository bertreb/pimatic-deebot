# pimatic-deebot
Pimatic plugin to control an Ecovacs Deebot cleaning robot

## Config of the plugin

```
email: "The email address for your deebots account"
password: "The password for your deebots account"
countrycode: "Your country code like 'DE'"
debug: "Debug mode. Writes debug messages to the pimatic log, if set to true."
```

## Config of a Deebot Device

Devices are added via the discovery function.
The automatic generated ID must not change. Its the unique reference to to vacuum

```
nickname:
  description: "A nickname for the deebot set via the app and then used in Pimatic
show:
  description: "If 'all': variables will be shown in the GUI except the variables selected in Attributes. If 'none': nothing will be shown in the GUI, except the ones selected in Attributes."
attributes:
  description: "Deebot attributes that will be hidden (show=all) or shown (show=none) in the GUI."
  items:[ # depending on type of your deebot
    "ChargeState", "FanSpeed", "CleanReport", "BatteryInfo",      "LifeSpan_filter" , "LifeSpan_main_brush", "LifeSpan_side_brush",
    "WaterLevel", "WaterBoxInfo"
  ]
```

The attributes are updated and visible in the Gui.
Tee deebot can be controlled via rules

deebot <Pimatic DeebBot ID> [clean|pause|resume|stop|charge]
