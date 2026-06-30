class_name MoveData
extends RefCounted

var api_name:     String = ""       # ex: "thunder-shock"
var display_name: String = ""       # ex: "Thunder Shock"
var type:         String = "normal"
var power:        int    = 0        # 0 = attaque de statut (pas utilisée en combat)
var damage_class: String = "physical"  # physical / special / status
var level_learned: int  = 1
