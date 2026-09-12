def bootstrap_main
  begin
    raise "body"
  ensure
    raise "cleanup"
  end
end

bootstrap_main
