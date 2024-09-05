#define TRACE_NVME_CQ_GET_CQE "nvme_cq_get_cqe"
#define TRACE_NVME_CQ_GOT_CQE "nvme_cq_got_cqe"
#define TRACE_NVME_CQ_SPIN "nvme_cq_spin"
#define TRACE_NVME_CQ_UPDATE_HEAD "nvme_cq_update_head"
#define TRACE_NVME_SQ_POST "nvme_sq_post"
#define TRACE_NVME_SQ_UPDATE_TAIL "nvme_sq_update_tail"
#define TRACE_NVME_SKIP_MMIO "nvme_skip_mmio"
#define TRACE_IOMMUFD_IOAS_MAP_DMA "iommufd_ioas_map_dma"
#define TRACE_IOMMUFD_IOAS_UNMAP_DMA "iommufd_ioas_unmap_dma"
#define TRACE_VFIO_IOMMU_TYPE1_MAP_DMA "vfio_iommu_type1_map_dma"
#define TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA "vfio_iommu_type1_unmap_dma"
#define TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS "vfio_iommu_type1_recycle_ephemeral_iovas"

#define TRACE_NVME_CQ_GET_CQE_DISABLED 1
#define TRACE_NVME_CQ_GOT_CQE_DISABLED 0
#define TRACE_NVME_CQ_SPIN_DISABLED 0
#define TRACE_NVME_CQ_UPDATE_HEAD_DISABLED 0
#define TRACE_NVME_SQ_POST_DISABLED 0
#define TRACE_NVME_SQ_UPDATE_TAIL_DISABLED 0
#define TRACE_NVME_SKIP_MMIO_DISABLED 0
#define TRACE_IOMMUFD_IOAS_MAP_DMA_DISABLED 0
#define TRACE_IOMMUFD_IOAS_UNMAP_DMA_DISABLED 0
#define TRACE_VFIO_IOMMU_TYPE1_MAP_DMA_DISABLED 0
#define TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA_DISABLED 0
#define TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS_DISABLED 0

extern bool TRACE_NVME_CQ_GET_CQE_ACTIVE;
extern bool TRACE_NVME_CQ_GOT_CQE_ACTIVE;
extern bool TRACE_NVME_CQ_SPIN_ACTIVE;
extern bool TRACE_NVME_CQ_UPDATE_HEAD_ACTIVE;
extern bool TRACE_NVME_SQ_POST_ACTIVE;
extern bool TRACE_NVME_SQ_UPDATE_TAIL_ACTIVE;
extern bool TRACE_NVME_SKIP_MMIO_ACTIVE;
extern bool TRACE_IOMMUFD_IOAS_MAP_DMA_ACTIVE;
extern bool TRACE_IOMMUFD_IOAS_UNMAP_DMA_ACTIVE;
extern bool TRACE_VFIO_IOMMU_TYPE1_MAP_DMA_ACTIVE;
extern bool TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA_ACTIVE;
extern bool TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS_ACTIVE;
