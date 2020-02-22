# #pimatic-deebot configuration options
module.exports = {
  title: "pimatic-deebot configuration options"
  type: "object"
  properties:
    email:
      descpription: "The email address for your deebots account"
      type: "string"
    password:
      descpription: "The password for your deebots account"
      type: "string"
    countrycode:
      descpription: "Your country code like 'DE'"
      type: "string"
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
}
