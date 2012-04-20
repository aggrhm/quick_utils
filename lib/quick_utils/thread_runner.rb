module QuickUtils
  class ThreadRunner

    def self.run(dataset, nthreads)
      threads = []
      count = dataset.size
      nthreads = 1 if count < nthreads
      bin_size = count / nthreads
      puts "Dividing #{count} items into sizes of #{bin_size} for #{nthreads} threads."
      t = 0
      while t < nthreads do
        subset = dataset[t*bin_size..t*bin_size+bin_size - 1]
        threads << Thread.new(subset) do |cs|
          yield cs
        end
        t = t + 1
      end
      threads.each {|t| t.join}
    end

  end
end

