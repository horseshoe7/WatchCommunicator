def add_logger
  pod 'XCGLogger', '~> 7.0.1'
end

target 'WatchCommunicator' do
  
  platform :ios, '12.3'
  inhibit_all_warnings!
  
  use_frameworks!

  add_logger
  
  target 'WatchCommunicatorTests' do
    inherit! :search_paths
    # Pods for testing
  end
end

target 'WatchCommunicator WatchKit Extension' do
  platform :watchos, '6.0'
  use_frameworks!
  add_logger
end
