require 'xcodeproj'

name = 'MinimalMC'
project = Xcodeproj::Project.new("#{name}.xcodeproj")
app = project.new_target(:application, name, :ios, '15.0')
tests = project.new_target(:unit_test_bundle, "#{name}Tests", :ios, '15.0')
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.jules.#{target.name}"
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  end
end
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'MinimalMC/Resources/Info.plist'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
end
tests.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/MinimalMC.app/MinimalMC'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
tests.add_dependency(app)
# SOURCE_ROOT paths avoid accidentally doubling nested group directory names.
[['MinimalMC/Sources', app], ['MinimalMC/Tests', tests]].each do |directory, target|
  group = project.main_group.new_group(target.name)
  Dir.glob("#{directory}/**/*.swift").sort.each do |path|
    reference = group.new_file(path, :source_root)
    target.add_file_references([reference])
  end
end
project.main_group.new_file('MinimalMC/Resources/Info.plist', :source_root)
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
project.save
scheme.save_as(project.path, name, true)
puts "Generated #{project.path}"
