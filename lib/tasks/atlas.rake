namespace :atlas do
  desc "Synchronize insales_atlas documents into storage/atlas"
  task sync: :environment do
    service = Atlas::SyncService.call(params: {})

    if service.success?
      puts "[atlas:sync] Synchronized #{service.result[:total_documents]} documents."
      puts "[atlas:sync] Index: #{service.result[:index_path]}"
    else
      puts "[atlas:sync] Failed:"
      service.errors.full_messages.each { |message| puts "  - #{message}" }
      exit(1)
    end
  end
end

