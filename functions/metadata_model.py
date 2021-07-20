import os
import yaml
from schematic.models.metadata import MetadataModel
from schematic import CONFIG

with open("config.yaml") as app_config_file:
    app_config = yaml.safe_load(app_config_file)
    schematic_config = app_config["schematic_config"]
    schematic_config_dir = os.path.dirname(schematic_config)

config = CONFIG.load_config(app_config["schematic_config"])

inputMModelLocation = CONFIG["model"]["input"]["location"]
inputMModelLocationType = CONFIG["model"]["input"]["file_type"]

if not os.path.isabs(inputMModelLocation):
    inputMModelLocation = os.path.join(schematic_config_dir, inputMModelLocation)
    inputMModelLocation = os.path.normpath(inputMModelLocation)

metadata_model = MetadataModel(inputMModelLocation, inputMModelLocationType)
