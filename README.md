# NewNetwork
Script to automate creation of Projects network

Requisite: Project must already exist

Net creation:
   - search for a free net number
   - create net and subnet
   - add the right DNS addresses to the subnet
   - attach the subnet to the right router
   
Security group handling:
   - add admin as admin to the Project (needed to modify the SG)
   - add SSH inbound rule from the right pool (e.g. 10.66.0.0/16)
   - enable ping reply
   - remove admin from the Project
   
