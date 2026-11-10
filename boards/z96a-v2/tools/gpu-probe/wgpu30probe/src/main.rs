fn main() {
    env_logger::init();
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::VULKAN,
        flags: if std::env::var("PROBE_DEFAULT_FLAGS").is_ok() { wgpu::InstanceFlags::default() } else { wgpu::InstanceFlags::ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER },
        memory_budget_thresholds: Default::default(),
        backend_options: Default::default(),
        display: None,
    });
    println!("instance created");
    let adapters = pollster::block_on(instance.enumerate_adapters(wgpu::Backends::VULKAN));
    println!("adapter count = {}", adapters.len());
    for a in &adapters {
        let i = a.get_info();
        println!("  adapter: name={:?} backend={:?} driver={:?} driver_info={:?} device={:?}",
            i.name, i.backend, i.driver, i.driver_info, i.device_type);
        let l = a.limits();
        println!("    limits: max_tex2d={} max_bind_groups={} max_storage_bufs={}",
            l.max_texture_dimension_2d, l.max_bind_groups, l.max_storage_buffers_per_shader_stage);
    }
    let r = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
        apply_limit_buckets: false,
    }));
    match r {
        Ok(a) => println!("request_adapter OK: {:?}", a.get_info().name),
        Err(e) => println!("request_adapter FAIL: {e}"),
    }

    let Some(adapter) = adapters.into_iter().next() else { return; };
    let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("vk"),
        required_features: wgpu::Features::empty(),
        required_limits: wgpu::Limits::downlevel_defaults(),
        memory_hints: wgpu::MemoryHints::MemoryUsage,
        trace: wgpu::Trace::Off,
        experimental_features: wgpu::ExperimentalFeatures::disabled(),
    })).expect("request_device failed");
    println!("device created");

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("t"),
        source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(r#"
@vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
    var p = array<vec2<f32>, 3>(vec2<f32>(-1.0,-1.0), vec2<f32>(3.0,-1.0), vec2<f32>(-1.0,3.0));
    return vec4<f32>(p[i], 0.0, 1.0);
}
@fragment fn fs() -> @location(0) vec4<f32> { return vec4<f32>(1.0, 0.5, 0.0, 1.0); }
"#)),
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("t"), bind_group_layouts: &[], immediate_size: 0 });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("t"),
        layout: Some(&layout),
        vertex: wgpu::VertexState { module: &shader, entry_point: Some("vs"), compilation_options: Default::default(), buffers: &[] },
        fragment: Some(wgpu::FragmentState {
            module: &shader, entry_point: Some("fs"), compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState { format: wgpu::TextureFormat::Rgba8Unorm, blend: None, write_mask: wgpu::ColorWrites::ALL })],
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview_mask: None,
        cache: None,
    });
    println!("pipeline created");

    let tex = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("off"),
        size: wgpu::Extent3d { width: 64, height: 64, depth_or_array_layers: 1 },
        mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let view = tex.create_view(&Default::default());
    let rb = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb"), size: 64*64*4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ, mapped_at_creation: false });
    let mut enc = device.create_command_encoder(&Default::default());
    {
        let mut rp = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("p"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view, depth_slice: None, resolve_target: None,
                ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color { r:0.0,g:0.0,b:1.0,a:1.0 }), store: wgpu::StoreOp::Store },
            })],
            depth_stencil_attachment: None, timestamp_writes: None, occlusion_query_set: None, multiview_mask: None,
        });
        rp.set_pipeline(&pipeline);
        rp.draw(0..3, 0..1);
    }
    enc.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo { texture: &tex, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
        wgpu::TexelCopyBufferInfo { buffer: &rb, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(64*4), rows_per_image: Some(64) } },
        wgpu::Extent3d { width: 64, height: 64, depth_or_array_layers: 1 },
    );
    queue.submit(Some(enc.finish()));
    let sl = rb.slice(..);
    sl.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None });
    let d = sl.get_mapped_range().expect("map failed");
    let c = ((32*64+32)*4) as usize;
    let px = [d[c], d[c+1], d[c+2], d[c+3]];
    println!("RENDER: center rgba={:?} -> {}", px, if px[0] > 200 && px[1] > 100 && px[1] < 160 && px[2] < 40 { "OK" } else { "FAIL" });
}

// appended: full render test
