module.exports = {
  title: "pimatic-deebot device config schemas"
  DeebotDevice: {
    title: "DeebotDevice config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:{
      nickname:
        description: "A nickname for the deebot"
        type: "string"
        required: false
      show:
        description: "If 'all': variables will be shown in the GUI except the variables selected in Attributes. If 'none': nothing will be shown in the GUI, except the ones selected in Attributes."
        type: "string"
        enum: ["none", "all"]
      attributes:
        description: "Deebot attributes that will be hidden (show=all) or shown (show=none) in the GUI."
        type: "array"
        format: "table"
        default: ["CleanReport","ChargeState","BatteryInfo"]
        items: 
          enum:[
            "ChargeState", "FanSpeed", "CleanReport", "BatteryInfo",
            "LifeSpan_filter" , "LifeSpan_main_brush", "LifeSpan_side_brush", 
            "WaterLevel", "WaterBoxInfo" 
          ]
    }
  }
}
