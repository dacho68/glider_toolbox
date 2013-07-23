function slocum_options = configRTSlocumFileOptions()
%CONFIGRTFILEOPTIONSSLOCUM  Configure download, conversion and loading options for Slocum files in real time.
%
%  slocum_options = CONFIGRTFILEOPTIONSSLOCUM() should return a struct with the
%  parameters that control the files to retrieve, how they will be converted,
%  and which files and data should be used in real time mode. The returned 
%  struct should have the following fields:
%    LOG_NAME_PATTERN: string with the name pattern of surface log files as
%      needed by function GETDOCKSERVERFILES. A remote log file should match 
%      this should match to be downloaded.
%    BIN_NAME_PATTERN: string with the name pattern of binary data files as
%      needed by function GETDOCKSERVERFILES and LOADSLOCUMDATA. A remote 
%      binary file should match this pattern to be downloaded, and the 
%      conversion to ascii format renames it according to this pattern and the 
%      replacement string in next field.
%    DBA_NAME_REPLACEMENT: string with the name pattern replacement to use when
%      converting binary files to ascii.
%    DBA_NAME_PATTERN_NAV: string with the name pattern of navigation ascii 
%      files to be loaded for processing by function LOADSLOCUMDATA. An ascii 
%      file should match this pattern to be loaded as a navigation file.
%    DBA_NAME_PATTERN_SCI: string with the name pattern of science ascii files
%      to be loaded for processing by LOADSLOCUMDATA. An ascii file should match
%      this pattern to be loaded as a science file by function LOADSLOCUMDATA.
%    DBA_TIME_SENSOR_NAV: string with the name of the timestamp sensor to use in
%      navigation files when combining data from different ascii files.
%    DBA_TIME_SENSOR_SCI: string with the name of the timestamp sensor to use in
%      science files when combining data from different ascii files.
%    DBA_SENSORS: string cell array with the name of the sensors to be included
%      in the processing. Restricting the list of sensors to load may reduce the
%      memory footprint.
%
%  Notes:
%
%  Examples:
%    slocum_options = configRTFileOptionsSlocum()
%
%  See also:
%    GETDOCKSERVERFILES
%    LOADSLOCUMDATA
%
%  Author: Joan Pau Beltran
%  Email: joanpau.beltran@socib.cat

%  Copyright (C) 2013
%  ICTS SOCIB - Servei d'observacio i prediccio costaner de les Illes Balears.
%
%  This program is free software: you can redistribute it and/or modify
%  it under the terms of the GNU General Public License as published by
%  the Free Software Foundation, either version 3 of the License, or
%  (at your option) any later version.
%
%  This program is distributed in the hope that it will be useful,
%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%  GNU General Public License for more details.
%
%  You should have received a copy of the GNU General Public License
%  along with this program.  If not, see <http://www.gnu.org/licenses/>.

  error(nargchk(0, 0, nargin, 'struct'));
  
  % Surface log files of any kind.
  slocum_options.log_name_pattern = '^\w+_(modem|network)_\d{8}T\d{6}\.log$';

  % All binary files, renamed or not:
  % slocum_options.bin_name_pattern = '^(.*)\.([smdtne]bd)$';
  % Already renamed binary files of all sizes.
  slocum_options.bin_name_pattern = '^(\w+-\d{4}-\d+-\d+-\d+)\.([smdtne]bd)$';
  
  % xbd to dba name replacement.
  slocum_options.dba_name_replacement = '$1-$2.dba';
  
  % Select navigation files to use. Restrict the character set if needed.
  slocum_options.dba_name_pattern_nav = '^.*-[smd]bd.dba$';
  
  % Select science files to use. Restrict the character set if needed.
  slocum_options.dba_name_pattern_sci = '^.*-[tne]bd.dba$';
  
  % Select time sensor column in navigation files.
  slocum_options.dba_time_sensor_nav = 'm_present_time';
  
  % Select time sensor column in science files.
  slocum_options.dba_time_sensor_sci = 'sci_m_present_time';
  
  % Sensors to load.
  slocum_options.dba_sensors = {
    'm_present_time'
    'm_lat'
    'm_lon'
    'm_gps_lat'
    'm_gps_lon'
    'm_gps_status'
    'c_wpt_lat'
    'c_wpt_lon'
    'm_pitch'
    'm_depth'
    'm_final_water_vx'
    'm_final_water_vy'
    'x_dr_state'
    'u_flntu_chlor_do'
    'u_flntu_turb_do'
    'u_flntu_chlor_sf'
    'u_flntu_turb_sf'
    'sci_m_present_time'
    'sci_ctd41cp_timestamp'
    'sci_water_pressure'
    'sci_water_cond'
    'sci_water_temp'
    'sci_flntu_chlor_ref'
    'sci_flntu_chlor_sig'
    'sci_flntu_chlor_units'
    'sci_flntu_temp'
    'sci_flntu_turb_ref'
    'sci_flntu_turb_sig'
    'sci_flntu_turb_units'
    'sci_flntu_timestamp'
    'sci_oxy3835_oxygen'
    'sci_oxy3835_saturation'
    'sci_oxy3835_temp'
    'sci_oxy3835_timestamp'
  };
  
end