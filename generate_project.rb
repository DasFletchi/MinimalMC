require 'xcodeproj'

project_name = 'MinimalMC'
project_path = "#{project_name}.xcodeproj"

project = Xcodeproj::Project.new(project_path)

# Target MinimalMC
app_target = project.new_target(:application, project_name, :ios, '15.0')
app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.jules.#{project_name}"
  config.build_settings['INFOPLIST_FILE'] = 'MinimalMC/Resources/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Development'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['ENABLE_PREVIEWS'] = 'YES'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
end

# Groups
sources_group = project.main_group.find_subpath(project_name, true)
app_group = sources_group.new_group('Sources', 'MinimalMC/Sources')
resources_group = sources_group.new_group('Resources', 'MinimalMC/Resources')
tests_group = project.main_group.find_subpath("#{project_name}Tests", true)
tests_src_group = tests_group.new_group('Tests', 'MinimalMC/Tests')

# Add Sources files
def add_files(dir_path, group, target)
  Dir.glob(File.join(dir_path, '**', '*.swift')).each do |file_path|
    file_ref = group.new_reference(file_path)
    target.add_file_references([file_ref])
  end
end

add_files('MinimalMC/Sources', app_group, app_target)

# Add Info.plist
info_plist_ref = resources_group.new_reference('MinimalMC/Resources/Info.plist')

# Tests Target
tests_target = project.new_target(:unit_test_bundle, "#{project_name}Tests", :ios, '15.0')
tests_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.jules.#{project_name}Tests"
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/#{project_name}.app/#{project_name}"
  config.build_settings['BUNDLE_LOADER'] = "$(TEST_HOST)"
end
project.targets.each do |t|
    if t.name == "#{project_name}Tests"
        t.add_dependency(app_target)
    end
end
add_files('MinimalMC/Tests', tests_src_group, tests_target)

project.save
puts "Project generated: #{project_path}"
